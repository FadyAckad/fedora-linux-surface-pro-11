#!/usr/bin/python3
"""Render synthetic packed RAW10 frames through libcamera's GPU debayer shaders the way DebayerEGL sets them up
(0.7.2): viewport = input size, 1920x1080 target, projection scale max(out/native), GL_LUMINANCE byte texture with
nearest filtering, uniforms as setShaderVariableValues() sets them. Mesa's software renderer, surfaceless EGL.

Run through debayer-model.sh, which sets up the mock root and copies in identity.vert, the patched
bayer_1x_packed.frag and the released one as bayer_1x_packed.frag.orig. Result with payload/camera/0007 on 0.7.2
(2026-09-27): the dark flat frame's square-to-square spread about 4 levels with the original shader, the patched one
with quad 0 identical to it, with quad 1 about 0.6 to 0.7 (the noise); RGGB and GRBG smooth scenes: mean
|difference| between the quad and the demosaic output below 0.2 levels, 99th percentile 1 level."""
import ctypes
import math
import os
import sys

os.environ.setdefault('PYOPENGL_PLATFORM', 'egl')
from OpenGL import EGL
import numpy as np


class _GL:
    """The few GLES2 entry points the test needs, straight from libGLESv2 through ctypes."""
    GL_RENDERER, GL_VERSION = 0x1F01, 0x1F02
    GL_VERTEX_SHADER, GL_FRAGMENT_SHADER = 0x8B31, 0x8B30
    GL_COMPILE_STATUS, GL_LINK_STATUS, GL_INFO_LOG_LENGTH = 0x8B81, 0x8B82, 0x8B84
    GL_TEXTURE0, GL_TEXTURE_2D = 0x84C0, 0x0DE1
    GL_UNPACK_ALIGNMENT, GL_PACK_ALIGNMENT = 0x0CF5, 0x0D05
    GL_LUMINANCE, GL_RGBA, GL_UNSIGNED_BYTE, GL_FLOAT = 0x1909, 0x1908, 0x1401, 0x1406
    GL_TEXTURE_MIN_FILTER, GL_TEXTURE_MAG_FILTER, GL_NEAREST = 0x2801, 0x2800, 0x2600
    GL_TEXTURE_WRAP_S, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE = 0x2802, 0x2803, 0x812F
    GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_FRAMEBUFFER_COMPLETE = 0x8D40, 0x8CE0, 0x8CD5
    GL_TRIANGLE_FAN, GL_NO_ERROR, GL_FALSE, GL_TRUE = 0x0006, 0, 0, 1

    def __init__(self):
        self.lib = ctypes.CDLL('libGLESv2.so.2')
        self.lib.glGetString.restype = ctypes.c_char_p
        for f in ('glGetUniformLocation', 'glGetAttribLocation', 'glCreateShader', 'glCreateProgram'):
            getattr(self.lib, f).restype = ctypes.c_int

    def __getattr__(self, name):
        return getattr(self.lib, name)


gl = _GL()
f32 = ctypes.c_float

W, H = 3840, 2640
STRIDE = W * 5 // 4
OW, OH = 1920, 1080


def egl_context():
    dpy = EGL.eglGetDisplay(EGL.EGL_DEFAULT_DISPLAY)
    major, minor = EGL.EGLint(), EGL.EGLint()
    assert EGL.eglInitialize(dpy, ctypes.pointer(major), ctypes.pointer(minor))
    assert EGL.eglBindAPI(EGL.EGL_OPENGL_ES_API)
    attribs = (EGL.EGLint * 5)(EGL.EGL_RENDERABLE_TYPE, EGL.EGL_OPENGL_ES2_BIT, EGL.EGL_SURFACE_TYPE, EGL.EGL_PBUFFER_BIT,
                               EGL.EGL_NONE)
    config = EGL.EGLConfig()
    n = EGL.EGLint()
    assert EGL.eglChooseConfig(dpy, attribs, ctypes.pointer(config), 1, ctypes.pointer(n)) and n.value > 0
    ctx = EGL.eglCreateContext(dpy, config, EGL.EGL_NO_CONTEXT,
                               (EGL.EGLint * 3)(EGL.EGL_CONTEXT_CLIENT_VERSION, 2, EGL.EGL_NONE))
    assert ctx
    assert EGL.eglMakeCurrent(dpy, EGL.EGL_NO_SURFACE, EGL.EGL_NO_SURFACE, ctx)
    print('GL_RENDERER', gl.glGetString(gl.GL_RENDERER).decode(), '| GL_VERSION', gl.glGetString(gl.GL_VERSION).decode())


def compile_shader(kind, env, path):
    src = (''.join(e + '\n' for e in env) + open(path).read()).encode()
    sh = gl.glCreateShader(kind)
    arr = (ctypes.c_char_p * 1)(src)
    gl.glShaderSource(sh, 1, arr, None)
    gl.glCompileShader(sh)
    ok, n = ctypes.c_int(), ctypes.c_int()
    gl.glGetShaderiv(sh, gl.GL_COMPILE_STATUS, ctypes.byref(ok))
    gl.glGetShaderiv(sh, gl.GL_INFO_LOG_LENGTH, ctypes.byref(n))
    buf = ctypes.create_string_buffer(max(1, n.value))
    gl.glGetShaderInfoLog(sh, len(buf), None, buf)
    if not ok.value:
        sys.exit(f'compile failed {path}:\n{buf.value.decode()}')
    if buf.value:
        print('compile log', path, buf.value.decode())
    return sh


def program(frag):
    env = ['#version 100', '#extension GL_OES_EGL_image_external: enable', '#define RAW10P']
    vs = compile_shader(gl.GL_VERTEX_SHADER, env, 'identity.vert')
    fs = compile_shader(gl.GL_FRAGMENT_SHADER, env, frag)
    p = gl.glCreateProgram()
    gl.glAttachShader(p, vs)
    gl.glAttachShader(p, fs)
    gl.glLinkProgram(p)
    ok = ctypes.c_int()
    gl.glGetProgramiv(p, gl.GL_LINK_STATUS, ctypes.byref(ok))
    if not ok.value:
        buf = ctypes.create_string_buffer(4096)
        gl.glGetProgramInfoLog(p, 4096, None, buf)
        sys.exit('link failed: ' + buf.value.decode())
    return p


def pack_raw10(v):
    v = v.astype(np.uint16)
    g = v.reshape(H, W // 4, 4)
    out = np.empty((H, W // 4, 5), np.uint8)
    out[:, :, :4] = (g >> 2).astype(np.uint8)
    out[:, :, 4] = ((g[:, :, 0] & 3) | (g[:, :, 1] & 3) << 2 | (g[:, :, 2] & 3) << 4 | (g[:, :, 3] & 3) << 6)
    return out.reshape(H, STRIDE)


def mosaic(rgb10, order):
    """rgb10: H x W x 3 values in 10-bit; order: 'RGGB' or 'GRBG'."""
    m = np.empty((H, W))
    pos = {'RGGB': {(0, 0): 0, (0, 1): 1, (1, 0): 1, (1, 1): 2}, 'GRBG': {(0, 0): 1, (0, 1): 0, (1, 0): 2, (1, 1): 1}}
    for (y, x), c in pos[order].items():
        m[y::2, x::2] = rgb10[y::2, x::2, c]
    return m


def render(p, raw_bytes, first_red, awb, quad):
    ids = (ctypes.c_uint * 2)()
    gl.glGenTextures(2, ids)
    tex, out = ids[0], ids[1]
    gl.glActiveTexture(gl.GL_TEXTURE0)
    gl.glBindTexture(gl.GL_TEXTURE_2D, tex)
    gl.glPixelStorei(gl.GL_UNPACK_ALIGNMENT, 1)
    data = np.ascontiguousarray(raw_bytes)
    gl.glTexImage2D(gl.GL_TEXTURE_2D, 0, gl.GL_LUMINANCE, STRIDE, H, 0, gl.GL_LUMINANCE, gl.GL_UNSIGNED_BYTE,
                    data.ctypes.data_as(ctypes.c_void_p))
    for k, v in ((gl.GL_TEXTURE_MIN_FILTER, gl.GL_NEAREST), (gl.GL_TEXTURE_MAG_FILTER, gl.GL_NEAREST),
                 (gl.GL_TEXTURE_WRAP_S, gl.GL_CLAMP_TO_EDGE), (gl.GL_TEXTURE_WRAP_T, gl.GL_CLAMP_TO_EDGE)):
        gl.glTexParameteri(gl.GL_TEXTURE_2D, k, v)
    gl.glBindTexture(gl.GL_TEXTURE_2D, out)
    gl.glTexImage2D(gl.GL_TEXTURE_2D, 0, gl.GL_RGBA, OW, OH, 0, gl.GL_RGBA, gl.GL_UNSIGNED_BYTE, None)
    fbo = ctypes.c_uint()
    gl.glGenFramebuffers(1, ctypes.byref(fbo))
    gl.glBindFramebuffer(gl.GL_FRAMEBUFFER, fbo)
    gl.glFramebufferTexture2D(gl.GL_FRAMEBUFFER, gl.GL_COLOR_ATTACHMENT0, gl.GL_TEXTURE_2D, out, 0)
    assert gl.glCheckFramebufferStatus(gl.GL_FRAMEBUFFER) == gl.GL_FRAMEBUFFER_COMPLETE
    gl.glActiveTexture(gl.GL_TEXTURE0)
    gl.glBindTexture(gl.GL_TEXTURE_2D, tex)
    gl.glUseProgram(p)
    native_w = (W - 2 * 4) & ~3
    native_h = H & ~1
    scale = max(OW / native_w, OH / native_h)
    trans = -(1.0 - scale)
    proj = (f32 * 16)(scale, 0, 0, 0, 0, scale, 0, 0, 0, 0, 1, 0, trans, trans, 0, 1)
    ident = (f32 * 9)(1, 0, 0, 0, 1, 0, 0, 0, 1)
    u = lambda name: gl.glGetUniformLocation(p, name.encode())
    gl.glUniform1i(u('tex_y'), 0)
    gl.glUniform2f(u('tex_bayer_first_red'), f32(first_red[0]), f32(first_red[1]))
    gl.glUniform2f(u('tex_size'), f32(W), f32(H))
    gl.glUniform2f(u('tex_step'), f32(1.0 / (STRIDE - 1)), f32(1.0 / (H - 1)))
    gl.glUniform1f(u('stride_factor'), f32(1.0))
    gl.glUniformMatrix4fv(u('proj_matrix'), 1, gl.GL_FALSE, proj)
    gl.glUniformMatrix3fv(u('ccm'), 1, gl.GL_FALSE, ident)
    gl.glUniform3f(u('blacklevel'), f32(16 / 255), f32(16 / 255), f32(16 / 255))
    gl.glUniform3f(u('awb'), f32(awb[0]), f32(awb[1]), f32(awb[2]))
    gl.glUniform1f(u('gamma'), f32(1 / 2.2))
    gl.glUniform1f(u('contrastExp'), f32(math.tan(math.pi / 4)))
    if quad is not None:
        loc = u('quad')
        assert loc >= 0, 'no quad uniform in the program'
        gl.glUniform1f(loc, f32(quad))
    vco = (f32 * 8)(-1, -1, -1, 1, 1, 1, 1, -1)
    tco = (f32 * 8)(0, 0, 0, 1, 1, 1, 1, 0)
    av, at = gl.glGetAttribLocation(p, b'vertexIn'), gl.glGetAttribLocation(p, b'textureIn')
    gl.glEnableVertexAttribArray(av)
    gl.glVertexAttribPointer(av, 2, gl.GL_FLOAT, gl.GL_TRUE, 8, vco)
    gl.glEnableVertexAttribArray(at)
    gl.glVertexAttribPointer(at, 2, gl.GL_FLOAT, gl.GL_TRUE, 8, tco)
    gl.glViewport(0, 0, W, H)
    gl.glDrawArrays(gl.GL_TRIANGLE_FAN, 0, 4)
    err = gl.glGetError()
    assert err == gl.GL_NO_ERROR, hex(err)
    buf = np.empty((OH, OW, 4), np.uint8)
    gl.glPixelStorei(gl.GL_PACK_ALIGNMENT, 1)
    gl.glReadPixels(0, 0, OW, OH, gl.GL_RGBA, gl.GL_UNSIGNED_BYTE, buf.ctypes.data_as(ctypes.c_void_p))
    gl.glDeleteFramebuffers(1, ctypes.byref(fbo))
    gl.glDeleteTextures(2, ids)
    return buf[:, :, :3].astype(np.float64)


def squares(img):
    T = 240
    tiles = np.array([[img[j:j + T, i:i + T].reshape(-1, 3).mean(0) for i in range(0, OW, T)]
                      for j in range(0, OH - T + 1, T)])
    return tiles.max(axis=(0, 1)) - tiles.min(axis=(0, 1)), img.reshape(-1, 3).mean(0)


def main():
    egl_context()
    old, new = program('bayer_1x_packed.frag.orig'), program('bayer_1x_packed.frag')
    rng = np.random.default_rng(3)

    # 1. A flat, dark, noisy grey frame (1.5 DN above black 64 at 10 bits, noise sigma 4 DN), RGGB, gain 16.
    raw = pack_raw10(np.clip(np.round(64 + 1.5 + rng.normal(0, 4.0, (H, W))), 0, 1023))
    a = render(old, raw, (0, 0), (16, 16, 16), None)
    b = render(new, raw, (0, 0), (16, 16, 16), 0.0)
    c = render(new, raw, (0, 0), (16, 16, 16), 1.0)
    print('dark flat, original shader:  square-to-square spread', np.round(squares(a)[0], 1), 'mean', np.round(squares(a)[1], 1))
    print('dark flat, patched, quad 0:  identical to the original:', bool(np.array_equal(a, b)))
    print('dark flat, patched, quad 1:  square-to-square spread', np.round(squares(c)[0], 1), 'mean', np.round(squares(c)[1], 1))

    # 2. Colour and geometry: a smooth colourful scene, both Bayer orders; quad output against the demosaic output.
    yy, xx = np.mgrid[0:H, 0:W]
    scene = np.stack([64 + 700 * xx / W, 64 + 700 * yy / H, 64 + 350 * (1 + np.sin(xx / 300.0) * np.cos(yy / 250.0))], -1)
    for order, fr in (('RGGB', (0, 0)), ('GRBG', (1, 0))):
        raw = pack_raw10(np.clip(np.round(mosaic(scene, order)), 0, 1023))
        d = render(new, raw, fr, (1, 1, 1), 0.0)
        q = render(new, raw, fr, (1, 1, 1), 1.0)
        diff = np.abs(d - q)
        print(f'{order} smooth scene: mean output demosaic {np.round(d.reshape(-1,3).mean(0),1)} quad {np.round(q.reshape(-1,3).mean(0),1)}; '
              f'mean |difference| per channel {np.round(diff.reshape(-1,3).mean(0),2)}, 99th percentile {np.round(np.percentile(diff.reshape(-1,3), 99, axis=0),1)}')


if __name__ == '__main__':
    main()
