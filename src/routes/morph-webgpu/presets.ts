/**
 * Presets as flat Float32Arrays for zero-allocation GPU upload.
 *
 * Layout matches the WGSL uniform struct exactly (208 bytes / 52 floats):
 *
 *  0: time           1: zoom           2: hue_shift      3: fbm_octaves
 *  4: res.x          5: res.y          6: mouse.x        7: mouse.y
 *  8: zoom_center.x  9: zoom_center.y 10: fbm_decay     11: fbm_freq_mul
 * 12: warp_scale    13: warp1_str     14: warp2_str     15: orb_count
 * 16: orb_radius    17: orb_intensity 18: orb_color_mode 19: fold_str
 * 20: fold_freq     21: normal_str    22: diffuse_str   23: spec_str
 * 24: spec_power    25: fresnel_f0    26: edge_glow_str 27: vignette_str
 * 28: grain_str     29: ridge_str     30: voronoi_str   31: voronoi_scale
 * 32-35: color_shadow (vec4)
 * 36-39: color_mid (vec4)
 * 40-43: color_bright (vec4)
 * 44-47: color_hot (vec4)
 * 48: wave_str      49: wave_freq     50: _pad          51: _pad
 */

export const UNIFORM_FLOATS = 52;
export const UNIFORM_BYTES = UNIFORM_FLOATS * 4;

// Indices for per-frame uniforms (set by JS each frame)
export const U_TIME = 0;
export const U_ZOOM = 1;
export const U_HUE_SHIFT = 2;
export const U_RES_X = 4;
export const U_RES_Y = 5;
export const U_MOUSE_X = 6;
export const U_MOUSE_Y = 7;
export const U_ZOOM_CENTER_X = 8;
export const U_ZOOM_CENTER_Y = 9;

// Indices for sharpness-related uniforms (used by audio VCF mapping)
export const U_FOLD_STR = 19;
export const U_SPEC_STR = 23;
export const U_SPEC_POWER = 24;
export const U_EDGE_GLOW_STR = 26;
export const U_RIDGE_STR = 29;
export const U_ORB_SHARPNESS = 29; // alias: no orb_sharpness in base shader, map to ridge_str
