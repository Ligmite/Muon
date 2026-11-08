// Muon - shared helpers. Placed before every stage.
// Pipeline convention: between passes the picture is stored encoded as
//   encoded = srgb_encode(scene_radiance / MU_HEADROOM)
// so that vanilla-drawn parts (entities, clouds, particles) and my terrain
// share one space. Every pass decodes, works in linear light, re-encodes.

override exposure_ev: f32 = 0.0;
override tonemap_op: u32 = 0u;
override grade_brightness: f32 = 1.0;
override grade_contrast: f32 = 1.05;
override grade_saturation: f32 = 1.0;
override grade_orange_boost: f32 = 0.0;
override grade_teal_boost: f32 = 0.05;
override grade_green_boost: f32 = -0.08;
override grade_green_hue: f32 = 0.0;
override vignette_intensity: f32 = 1.0;
override bloom_intensity: f32 = 1.0;
override bloom_spread: f32 = 1.0;
override bloom_threshold: f32 = 1.0;
override lens_flare: bool = true;
override lens_flare_intensity: f32 = 0.4;
override sun_intensity: f32 = 7.0;
override shadows_enabled: bool = true;
override shadow_softness: f32 = 1.0;
override shadow_strength: f32 = 1.0;
override diffuse_wrap: f32 = 0.25;
override sss_strength: f32 = 0.6;
override emission_strength: f32 = 2.5;
override water_waves: f32 = 1.0;
override water_speed: f32 = 1.2;
override water_fog: f32 = 1.0;
override water_fresnel: f32 = 1.0;
override water_refraction: f32 = 1.0;
override reflections: bool = true;
override ao_strength: f32 = 0.5;
override ao_radius: f32 = 2.0;
override ssr_mode: u32 = 1u;
override ssr_intensity: f32 = 1.0;
override vl_intensity: f32 = 0.6;
override fog_density: f32 = 0.25;
override sky_fog_blend: f32 = 0.35;
override sky_intensity: f32 = 1.0;
override sky_saturation: f32 = 1.2;
override hdr_enabled: bool = false;
override hdr_peak_nits: f32 = 1000.0;
override hdr_paper_white: f32 = 203.0;
override output_linear: bool = false;
override fxaa_enabled: bool = true;
override auto_exposure: u32 = 0u;
override ae_bias: f32 = 0.0;
override ae_min: f32 = -1.0;
override ae_max: f32 = 0.0;
override cas_enabled: bool = true;
override cas_intensity: f32 = 0.5;
override dither_enabled: bool = true;
override lut_enabled: bool = false;
override lut_strength: f32 = 1.0;
override underwater_density: f32 = 0.6;
override clouds_enabled: bool = true;
override ambient_intensity: f32 = 1.0;
override cloud_coverage: f32 = 0.35;
override cloud_density: f32 = 1.0;

const MU_PI: f32 = 3.14159265;
// The inter-pass picture is sRGB-encoded with this much headroom. 2.0 clipped
// the sky: Rayleigh blue is several times brighter than the terrain, so the
// whole dome saturated to white. 4.0 keeps the blue and the cloud tops.
const MU_HEADROOM: f32 = 4.0;

const MU_709_TO_2020 = mat3x3<f32>(vec3<f32>(0.6274257, 0.3292891, 0.0433502), vec3<f32>(0.0690274, 0.9195786, 0.0113614), vec3<f32>(0.0163664, 0.0880289, 0.8956843));
const MU_2020_TO_709 = mat3x3<f32>(vec3<f32>(1.6603441, -0.5875716, -0.0728802), vec3<f32>(-0.1243787, 1.1328371, -0.0083587), vec3<f32>(-0.0181127, -0.1005838, 1.1186213));

fn mu_sat(x: f32) -> f32 { return clamp(x, 0.0, 1.0); }
fn mu_sat3(x: vec3<f32>) -> vec3<f32> { return clamp(x, vec3<f32>(0.0), vec3<f32>(1.0)); }
fn mu_max0(x: vec3<f32>) -> vec3<f32> { return max(x, vec3<f32>(0.0)); }
fn mu_sqr(x: f32) -> f32 { return x * x; }
fn mu_luma709(c: vec3<f32>) -> f32 { return dot(c, vec3<f32>(0.2126, 0.7152, 0.0722)); }
fn mu_luma2020(c: vec3<f32>) -> f32 { return dot(c, vec3<f32>(0.2627, 0.6780, 0.0593)); }

// ---------------------------------------------------------------------
//   Transfer functions
// ---------------------------------------------------------------------

// Accurate sRGB, used for the inter-pass encoding (exactly invertible).
fn mu_srgb_encode(x: vec3<f32>) -> vec3<f32> {
    let c = max(x, vec3<f32>(0.0));
    let lo = c * 12.92;
    let hi = 1.055 * pow(c, vec3<f32>(1.0 / 2.4)) - vec3<f32>(0.055);
    return select(hi, lo, c < vec3<f32>(0.0031308));
}

fn mu_srgb_decode(x: vec3<f32>) -> vec3<f32> {
    let c = max(x, vec3<f32>(0.0));
    let lo = c / 12.92;
    let hi = pow((c + vec3<f32>(0.055)) / 1.055, vec3<f32>(2.4));
    return select(hi, lo, c < vec3<f32>(0.04045));
}

fn mu_scene_decode(encoded: vec3<f32>) -> vec3<f32> {
    return mu_srgb_decode(encoded) * MU_HEADROOM;
}

fn mu_scene_encode(radiance: vec3<f32>) -> vec3<f32> {
    return mu_srgb_encode(radiance / MU_HEADROOM);
}

// ---------------------------------------------------------------------
//   Colour grade
//
// A filmic grade of Muon's own: exposure and log-contrast in scene-linear
// Rec.2020, then a gentle hue-aware saturation pass and a cool-shadow /
// warm-highlight split in the display domain. The published Lottes curve is
// the default tone map because its shoulder keeps sunlit sand and cloud tops
// from clipping.
// ---------------------------------------------------------------------

fn mu_cubic_smooth(x: f32) -> f32 { return x * x * (3.0 - 2.0 * x); }

fn mu_pulse(x_in: f32, center: f32, width: f32, period: f32) -> f32 {
    var x = (x_in - center + 0.5 * period) / period;
    x = fract(x) * period - 0.5 * period;
    let t = abs(x) / width;
    if (t > 1.0) { return 0.0; }
    return 1.0 - mu_cubic_smooth(t);
}

fn mu_rgb_to_hsl(c: vec3<f32>) -> vec3<f32> {
    let mx = max(c.r, max(c.g, c.b));
    let mn = min(c.r, min(c.g, c.b));
    let d = mx - mn;
    let e = 0.000001;
    var h = 0.0;
    if (d > e) {
        if (mx == c.r) {
            h = (c.g - c.b) / d;
            if (h < 0.0) { h = h + 6.0; }
        } else if (mx == c.g) {
            h = (c.b - c.r) / d + 2.0;
        } else {
            h = (c.r - c.g) / d + 4.0;
        }
        h = h / 6.0;
    }
    return vec3<f32>(h, d / (mx + e), mx);
}

fn mu_hsl_to_rgb(c: vec3<f32>) -> vec3<f32> {
    let sat = clamp(c.y, 0.0, 1.0);
    let val = clamp(c.z, 0.0, 1.0);
    let h = c.x;
    let pr = abs(fract(h + 1.0) * 6.0 - 3.0);
    let pg = abs(fract(h + 0.6666667) * 6.0 - 3.0);
    let pb = abs(fract(h + 0.3333333) * 6.0 - 3.0);
    let tr = clamp(pr - 1.0, 0.0, 1.0);
    let tg = clamp(pg - 1.0, 0.0, 1.0);
    let tb = clamp(pb - 1.0, 0.0, 1.0);
    let r = val * (1.0 + (tr - 1.0) * sat);
    let g = val * (1.0 + (tg - 1.0) * sat);
    let b = val * (1.0 + (tb - 1.0) * sat);
    return vec3<f32>(r, g, b);
}

fn mu_isolate_hue(hsl: vec3<f32>, center: f32, width: f32) -> f32 {
    if (hsl.y < 1e-2 || hsl.z < 1e-2) { return 0.0; }
    return mu_pulse(hsl.x * 360.0, center, width, 360.0);
}

// ---- dithering (ordered 16x16, 8 bit)
fn mu_bayer2(a: vec2<f32>) -> f32 {
    let f = floor(a);
    return fract(dot(f, vec2<f32>(0.5, f.y * 0.75)));
}
fn mu_bayer4(a: vec2<f32>) -> f32 { return 0.25 * mu_bayer2(0.5 * a) + mu_bayer2(a); }
fn mu_bayer8(a: vec2<f32>) -> f32 { return 0.25 * mu_bayer4(0.5 * a) + mu_bayer2(a); }
fn mu_bayer16(a: vec2<f32>) -> f32 { return 0.25 * mu_bayer8(0.5 * a) + mu_bayer2(a); }

// rgb: linear Rec.2020, [0, inf)
fn mu_grade_input(rgb_in: vec3<f32>) -> vec3<f32> {
    var rgb = mu_max0(rgb_in) * (0.85 * grade_brightness);

    // Contrast about the 18% grey point, in log2 space.
    let mid = log2(0.18);
    rgb = exp2(grade_contrast * (log2(max(rgb, vec3<f32>(1e-6))) - vec3<f32>(mid)) + vec3<f32>(mid));

    let lum = mu_luma2020(rgb);
    rgb = mu_max0(mix(vec3<f32>(lum), rgb, 0.98 * grade_saturation));
    return rgb;
}

// rgb: linear Rec.709 in [0, 1] (SDR) or Reinhard-compressed (HDR)
fn mu_grade_output(rgb_in: vec3<f32>) -> vec3<f32> {
    // Grade in a roughly perceptual domain.
    let rgb0 = sqrt(max(rgb_in, vec3<f32>(0.0)));
    var hsl = mu_rgb_to_hsl(rgb0);

    // Gentle hue bands: warm orange, cool teal, leafy green. The values are
    // Muon's own, chosen against the same reference photographs as the rest.
    let orange = mu_isolate_hue(hsl, 32.0, 22.0);
    hsl.y = hsl.y * (1.0 + grade_orange_boost * orange);

    let teal = mu_isolate_hue(hsl, 200.0, 24.0);
    hsl.y = hsl.y * (1.0 + grade_teal_boost * teal);

    let green = mu_isolate_hue(hsl, 105.0, 44.0);
    hsl.x = hsl.x + (grade_green_hue / 360.0) * green;
    hsl.y = hsl.y * (1.0 + grade_green_boost * green);

    var rgb = mu_hsl_to_rgb(hsl);

    // Split tone: cool the shadows, warm the highlights. This is the part that
    // gives the picture depth instead of a flat mid-grey wash.
    let l = mu_luma709(rgb);
    let highs = smoothstep(0.30, 1.0, l);
    let shadows = 1.0 - smoothstep(0.0, 0.60, l);
    rgb = rgb * mix(vec3<f32>(0.92, 0.99, 1.08), vec3<f32>(1.10, 1.02, 0.90), highs);
    rgb = rgb * mix(1.0, 1.05, shadows);

    // A small S-curve for contrast and colour separation.
    rgb = mix(rgb, smoothstep(vec3<f32>(0.0), vec3<f32>(1.0), rgb), 0.12);

    return rgb * rgb;
}

fn mu_vignette(uv: vec2<f32>) -> f32 {
    let size = 16.0;
    let intensity = 0.08 * vignette_intensity;
    let t = abs(cos(2.0 * frame.time));
    let pulse = 1.0 - t * (2.0 - t);
    var v = size * (uv.x * uv.y - uv.x) * (uv.x * uv.y - uv.y);
    v = pow(max(v, 0.0), intensity + 0.3 * frame.blindness + 0.2 * pulse * frame.darkness);
    return v;
}

// ---------------------------------------------------------------------
//   Tonemapping operators (the reference + HDR fork)
// ---------------------------------------------------------------------

fn mu_tonemap_lottes(rgb: vec3<f32>) -> vec3<f32> {
    let a = 1.5;
    let d = 0.91;
    let hdr_max = 8.0;
    let mid_in = 0.26;
    let mid_out = 0.32;
    let b = (-pow(mid_in, a) + pow(hdr_max, a) * mid_out)
        / ((pow(hdr_max, a * d) - pow(mid_in, a * d)) * mid_out);
    let c = (pow(hdr_max, a * d) * pow(mid_in, a) - pow(hdr_max, a) * pow(mid_in, a * d) * mid_out)
        / ((pow(hdr_max, a * d) - pow(mid_in, a * d)) * mid_out);
    return pow(rgb, vec3<f32>(a)) / (pow(rgb, vec3<f32>(a * d)) * b + c);
}

fn mu_tonemap_hejl_burgess(rgb_in: vec3<f32>) -> vec3<f32> {
    var rgb = rgb_in * min(vec3<f32>(1.0), vec3<f32>(1.0) - 0.8 * exp(rgb_in * (-1.0 / 0.004)));
    rgb = (rgb * (6.2 * rgb + vec3<f32>(0.5))) / (rgb * (6.2 * rgb + vec3<f32>(1.7)) + vec3<f32>(0.06));
    return rgb * (rgb * (rgb * 0.305306011 + vec3<f32>(0.682171111)) + vec3<f32>(0.012522878));
}

fn mu_uncharted2_partial(x: vec3<f32>) -> vec3<f32> {
    let a = 0.15;
    let b = 0.50;
    let c = 0.10;
    let d = 0.20;
    let e = 0.02;
    let f = 0.30;
    return ((x * (a * x + vec3<f32>(c * b)) + vec3<f32>(d * e)) / (x * (a * x + vec3<f32>(b)) + vec3<f32>(d * f))) - vec3<f32>(e / f);
}

fn mu_tonemap_uncharted2(rgb: vec3<f32>) -> vec3<f32> {
    let curr = mu_uncharted2_partial(rgb * 2.0);
    let white_scale = vec3<f32>(1.0) / mu_uncharted2_partial(vec3<f32>(11.2));
    return curr * white_scale;
}

fn mu_tonemap_tech(rgb: vec3<f32>) -> vec3<f32> {
    var a = rgb * min(vec3<f32>(1.0), vec3<f32>(1.0) - exp(rgb * (-1.0 / 0.038)));
    a = mix(a, rgb, rgb * rgb);
    return a / (a + vec3<f32>(0.6));
}

fn mu_tonemap_reinhard_jodie(rgb: vec3<f32>) -> vec3<f32> {
    let r = rgb / (rgb + vec3<f32>(1.0));
    return mix(rgb / (mu_luma2020(rgb) + 1.0), r, r);
}

fn mu_tonemap_sdr(rgb: vec3<f32>) -> vec3<f32> {
    let x = mu_max0(rgb);
    if (tonemap_op == 1u) { return mu_tonemap_hejl_burgess(x); }
    if (tonemap_op == 2u) { return mu_tonemap_uncharted2(x); }
    if (tonemap_op == 3u) { return mu_tonemap_tech(x); }
    if (tonemap_op == 4u) { return mu_tonemap_reinhard_jodie(x); }
    return mu_tonemap_lottes(x);
}

// HDR: keep the filmic SDR curve in the toe and hand the highlights to a soft
// exponential shoulder at the display's peak, relative to paper white. The
// approach follows the the reference HDR fork; the implementation is Muon's own.
fn mu_hdr_shoulder(rgb: vec3<f32>, peak: f32) -> vec3<f32> {
    let x = mu_max0(rgb);
    let lottes = mu_tonemap_lottes(x);
    let shoulder = peak * (vec3<f32>(1.0) - exp(-x / max(peak, 0.01)));
    let blend = smoothstep(0.45, 1.0, mu_luma2020(x));
    return mix(lottes, shoulder, blend);
}

fn mu_tonemap_hdr(rgb_in: vec3<f32>) -> vec3<f32> {
    let peak = max(hdr_peak_nits / hdr_paper_white, 1.0);
    if (tonemap_op == 2u) {
        return mu_hdr_shoulder(mu_tonemap_uncharted2(mu_max0(rgb_in)), peak);
    }
    return mu_hdr_shoulder(mu_max0(rgb_in), peak);
}

fn mu_reinhard(x: vec3<f32>) -> vec3<f32> { return x / (x + vec3<f32>(1.0)); }
fn mu_reinhard_inverse(x: vec3<f32>) -> vec3<f32> { return x / max(vec3<f32>(1.0) - x, vec3<f32>(1e-4)); }

// ---------------------------------------------------------------------
//   Atmosphere (single scattering, quadratic step distribution)
// ---------------------------------------------------------------------

fn mu_ray_sphere_far(ro: vec3<f32>, rd: vec3<f32>, r: f32) -> f32 {
    let b = dot(ro, rd);
    let c = dot(ro, ro) - r * r;
    let disc = b * b - c;
    if (disc < 0.0) { return -1.0; }
    return -b + sqrt(disc);
}

// Radiance of the sky along `dir` for a light at `sun`, in scene units.
fn mu_atmosphere(dir_in: vec3<f32>, sun: vec3<f32>, steps: i32) -> vec3<f32> {
    let planet = 6371.0;
    let top = 6471.0;
    let h_r = 8.0;
    let h_m = 1.2;
    let beta_r = vec3<f32>(5.8e-3, 13.5e-3, 33.1e-3);
    let beta_m = 21e-3;

    let d = normalize(vec3<f32>(dir_in.x, max(dir_in.y, 0.004), dir_in.z));
    let ro = vec3<f32>(0.0, planet + 0.2, 0.0);
    let t_max = mu_ray_sphere_far(ro, d, top);
    if (t_max < 0.0) { return vec3<f32>(0.0); }

    var opt_r = 0.0;
    var opt_m = 0.0;
    var sum_r = vec3<f32>(0.0);
    var sum_m = vec3<f32>(0.0);
    let n = f32(steps);

    for (var i = 0; i < steps; i = i + 1) {
        let u = (f32(i) + 0.5) / n;
        let ds = t_max * 2.0 * u / n;
        let p = ro + d * (t_max * u * u);
        let h = length(p) - planet;
        let dr = exp(-h / h_r) * ds;
        let dm = exp(-h / h_m) * ds;
        opt_r = opt_r + dr;
        opt_m = opt_m + dm;

        let tl = mu_ray_sphere_far(p, sun, top);
        let lds = max(tl, 0.0) / 4.0;
        var lr = 0.0;
        var lm = 0.0;
        for (var j = 0; j < 4; j = j + 1) {
            let q = p + sun * (lds * (f32(j) + 0.5));
            let hq = length(q) - planet;
            lr = lr + exp(-hq / h_r) * lds;
            lm = lm + exp(-hq / h_m) * lds;
        }
        let tau = beta_r * (opt_r + lr) + vec3<f32>(beta_m * 1.1 * (opt_m + lm))
            + vec3<f32>(0.65e-3, 1.881e-3, 0.085e-3) * (1.5 * (opt_r + lr));
        let att = exp(-tau);
        sum_r = sum_r + att * dr;
        sum_m = sum_m + att * dm;
    }

    let mu = dot(d, sun);
    let g = 0.76;
    let phase_r = 3.0 / (16.0 * MU_PI) * (1.0 + mu * mu);
    let phase_m = 3.0 / (8.0 * MU_PI) * ((1.0 - g * g) * (1.0 + mu * mu))
        / ((2.0 + g * g) * pow(1.0 + g * g - 2.0 * g * mu, 1.5));
    return 6.00 * (sum_r * beta_r * phase_r + sum_m * (beta_m * phase_m));
}

// Full sky: sun scattering plus a faint moon-lit night sky.
fn mu_sky_radiance(dir: vec3<f32>, steps: i32) -> vec3<f32> {
    var c = mu_atmosphere(dir, frame.sun_direction, steps);
    c = c + mu_atmosphere(dir, frame.moon_direction, max(steps / 2, 4)) * vec3<f32>(0.0030, 0.0040, 0.0070);
    c = c + vec3<f32>(0.0008, 0.0012, 0.0028);
    return c;
}

// Cheap sun colour (direct light), warmer near the horizon.
fn mu_sun_color(sun_y: f32) -> vec3<f32> {
    let warm = vec3<f32>(1.00, 0.42, 0.14);
    let white = vec3<f32>(1.00, 0.91, 0.76);
    let vis = smoothstep(-0.06, 0.10, sun_y);
    return mix(warm, white, smoothstep(0.02, 0.40, sun_y)) * vis;
}

fn mu_moon_color(moon_y: f32) -> vec3<f32> {
    return vec3<f32>(0.40, 0.52, 0.90) * 0.035 * smoothstep(-0.08, 0.12, moon_y);
}

// Camera-relative world position -> (uv.xy, reversed depth). z < 0 when behind camera.
fn mu_project(p: vec3<f32>) -> vec3<f32> {
    let v = frame.view * vec4<f32>(p, 1.0);
    let c = frame.projection * v;
    if (c.w <= 0.000001) { return vec3<f32>(-10.0, -10.0, -10.0); }
    let ndc = c.xyz / c.w;
    return vec3<f32>(ndc.x * 0.5 + 0.5, 0.5 - ndc.y * 0.5, ndc.z);
}

fn mu_ign(p: vec2<f32>, i: u32) -> f32 {
    let q = p + vec2<f32>(5.588238 * f32(i % 64u));
    return fract(52.9829189 * fract(dot(q, vec2<f32>(0.06711056, 0.00583715))));
}


// ---------------------------------------------------------------------
//   Clouds (weather dependent), sun/moon/stars and the complete sky
// ---------------------------------------------------------------------

fn mu_hash3(p: vec3<f32>) -> f32 {
    var q = fract(p * 0.1031);
    q = q + vec3<f32>(dot(q, q.zyx + vec3<f32>(31.32)));
    return fract((q.x + q.y) * q.z);
}

fn mu_hash2(p: vec2<f32>) -> f32 {
    var q = fract(vec3<f32>(p.x, p.y, p.x) * vec3<f32>(0.1031, 0.1030, 0.0973));
    q = q + vec3<f32>(dot(q, q.yzx + vec3<f32>(31.32)));
    return fract((q.x + q.y) * q.z);
}

fn mu_noise2(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (vec2<f32>(3.0) - 2.0 * f);
    let a = mu_hash2(i);
    let b = mu_hash2(i + vec2<f32>(1.0, 0.0));
    let c = mu_hash2(i + vec2<f32>(0.0, 1.0));
    let d = mu_hash2(i + vec2<f32>(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

fn mu_fbm2(p0: vec2<f32>, octaves: i32) -> f32 {
    var p = p0;
    var sum = 0.0;
    var amp = 0.5;
    var norm = 0.0;
    for (var i = 0; i < 6; i = i + 1) {
        if (i >= octaves) { break; }
        sum = sum + amp * mu_noise2(p);
        norm = norm + amp;
        p = p * 2.03 + vec2<f32>(17.3, 9.1);
        amp = amp * 0.5;
    }
    return sum / max(norm, 1e-5);
}

fn mu_noise3(p: vec3<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (vec3<f32>(3.0) - 2.0 * f);
    let n000 = mu_hash3(i);
    let n100 = mu_hash3(i + vec3<f32>(1.0, 0.0, 0.0));
    let n010 = mu_hash3(i + vec3<f32>(0.0, 1.0, 0.0));
    let n110 = mu_hash3(i + vec3<f32>(1.0, 1.0, 0.0));
    let n001 = mu_hash3(i + vec3<f32>(0.0, 0.0, 1.0));
    let n101 = mu_hash3(i + vec3<f32>(1.0, 0.0, 1.0));
    let n011 = mu_hash3(i + vec3<f32>(0.0, 1.0, 1.0));
    let n111 = mu_hash3(i + vec3<f32>(1.0, 1.0, 1.0));
    let x00 = n000 + (n100 - n000) * u.x;
    let x10 = n010 + (n110 - n010) * u.x;
    let x01 = n001 + (n101 - n001) * u.x;
    let x11 = n011 + (n111 - n011) * u.x;
    let y0 = x00 + (x10 - x00) * u.y;
    let y1 = x01 + (x11 - x01) * u.y;
    return y0 + (y1 - y0) * u.z;
}

fn mu_cloud_fbm(p_in: vec3<f32>, octaves: i32) -> f32 {
    var p = p_in;
    var a = 0.5;
    var sum = 0.0;
    var norm = 0.0;
    for (var i = 0; i < octaves; i = i + 1) {
        sum = sum + a * mu_noise3(p);
        norm = norm + a;
        p = p * 2.03 + vec3<f32>(17.0, 3.0, 11.0);
        a = a * 0.5;
    }
    return sum / norm;
}

fn mu_hg(mu: f32, g: f32) -> f32 {
    let g2 = g * g;
    return (1.0 - g2) / (4.0 * MU_PI * pow(1.0 + g2 - 2.0 * g * mu, 1.5));
}

// 0 in fair weather, 1 in rain; thunder adds on top.
fn mu_wetness() -> f32 { return mu_sat(max(frame.rain, frame.thunder)); }

// Billowy 3D noise: folding around the midpoint gives cloud tops their
// cauliflower silhouette instead of the soft blobs plain fbm produces.
fn mu_billow3(p0: vec3<f32>, octaves: i32) -> f32 {
    var p = p0;
    var sum = 0.0;
    var amp = 0.5;
    var norm = 0.0;
    for (var i = 0; i < 5; i = i + 1) {
        if (i >= octaves) { break; }
        let n = abs(mu_noise3(p) * 2.0 - 1.0);
        sum = sum + (1.0 - n) * amp;
        norm = norm + amp;
        p = p * 2.11 + vec3<f32>(3.1, 7.7, 13.3);
        amp = amp * 0.5;
    }
    return sum / max(norm, 1e-5);
}

// A 2D coverage chart sampled on the cloud base. Doing coverage here, rather
// than from the 3D density alone, is what leaves actual holes between cloud
// masses: a vertical ray either enters a cloud column or it does not.
fn mu_cloud_map(p: vec2<f32>) -> f32 {
    let wind = vec2<f32>(frame.time * 2.0, frame.time * 0.65);
    let q = (p + wind) * 0.0040;
    let big = mu_fbm2(q, 4);
    let mid = mu_fbm2(q * 3.1 + vec2<f32>(11.0, 7.0), 3);
    let fine = mu_fbm2(q * 9.0 + vec2<f32>(3.0, 19.0), 2);
    return mu_sat((big - 0.48) * 3.2 + (mid - 0.5) * 0.30 + (fine - 0.5) * 0.10 + 0.5);
}

// Project the point toward the sun onto the cloud base and read the coverage
// chart there. Cheap dappled light, and the reason a broken cloud deck reads as
// a layer instead of a painted backdrop.
fn mu_cloud_shadow(world_pos: vec3<f32>) -> f32 {
    let sun = frame.sun_direction;
    if (sun.y <= 0.05) { return 1.0; }
    let base = mix(380.0, 280.0, mu_wetness());
    let t = (base - world_pos.y) / sun.y;
    if (t <= 0.0) { return 1.0; }
    let q = world_pos.xz + sun.xz * t;
    let coverage = clamp(cloud_coverage + 0.30 * mu_wetness(), 0.0, 1.0);
    let thr = 0.72 - coverage * 0.36;
    let m = smoothstep(thr, thr + 0.18, mu_cloud_map(q));
    return 1.0 - m * 0.55;
}

// Each cloud column gets its own base and thickness, so the deck is not one
// perfectly level slab.
fn mu_cloud_height(p: vec3<f32>, base: f32, thick: f32) -> f32 {
    // A cloud column can sit up to ~95 blocks above/below the nominal base and
    // be 55–145% as thick; this is the vertical break-up the deck needs.
    let off = (mu_noise2(p.xz * 0.0026 + vec2<f32>(frame.time * 0.008, 3.0)) - 0.5) * 190.0;
    let scale = 0.55 + 0.90 * mu_noise2(p.xz * 0.0017 + vec2<f32>(7.0, 1.0));
    return (p.y - base - off) / max(thick * scale, 1e-3);
}

fn mu_cloud_density(p: vec3<f32>, base: f32, thick: f32, coverage: f32) -> f32 {
    let h = mu_cloud_height(p, base, thick);
    if (h <= 0.0 || h >= 1.0) { return 0.0; }
    let thr = 0.72 - coverage * 0.36;
    let mask = smoothstep(thr, thr + 0.12, mu_cloud_map(p.xz));
    let t = frame.time;
    // Two scales: the low one builds the towers, the high one eats their edges
    // into cauliflower detail instead of leaving a smooth white block.
    let q = vec3<f32>(p.x + t * 1.2, p.y * 1.5, p.z + t * 0.5) * 0.0060;
    let billow = mu_billow3(q, 3);
    let q2 = vec3<f32>(p.x - t * 0.7, p.y * 2.3, p.z + t * 0.9) * 0.014;
    let erode = mu_billow3(q2, 2);
    let edge = smoothstep(0.28, 0.68, billow);
    let detail = edge * mix(0.55, 1.0, erode);
    let profile = smoothstep(0.0, 0.12, h) * (1.0 - smoothstep(0.60, 1.0, h));
    return mask * detail * profile * cloud_density;
}

fn mu_cloud_lighting(p: vec3<f32>, density: f32, base: f32, thick: f32, coverage: f32) -> vec3<f32> {
    let sun = frame.sun_direction;
    var optical = density * 0.6;
    var step = 10.0;
    var pos = p;
    for (var i = 0; i < 3; i = i + 1) {
        pos = pos + sun * step;
        optical = optical + mu_cloud_density(pos, base, thick, coverage) * step * 0.10;
        step = step * 1.9;
    }
    let beer = exp(-optical);
    let multi = exp(-optical * 0.25);
    let powder = 1.0 - exp(-optical * 2.5);
    let day = smoothstep(-0.08, 0.12, sun.y);
    let warmth = 1.0 - smoothstep(0.0, 0.35, sun.y);
    let sun_color = mix(vec3<f32>(1.0), vec3<f32>(1.0, 0.58, 0.31), warmth * day);
    let sun_radiance = mix(vec3<f32>(0.28, 0.36, 0.55) * 0.10, sun_color * 2.40, day);
    let h = mu_sat(mu_cloud_height(p, base, thick));
    let ambient = mix(frame.fog_color * 0.65, frame.sky_color * 1.00, 0.6) * (0.30 + 0.70 * h) * day;
    return ambient + sun_radiance * (beer * 0.72 + multi * 0.28) * (0.35 + 0.65 * powder);
}

// Volumetric cumulus. The layer is anchored in the world (camera position is
// the ray origin), so walking moves the clouds by their real parallax. The
// march is capped and faded before the ray gets too shallow.
fn mu_clouds(dir: vec3<f32>) -> vec4<f32> {
    let origin = frame.camera_position;
    let wet = mu_wetness();
    let base = mix(380.0, 280.0, wet);
    let thick = mix(160.0, 120.0, wet) + 100.0 * frame.thunder;
    let coverage = clamp(cloud_coverage + 0.30 * wet, 0.0, 1.0);
    if (dir.y <= 0.005) { return vec4<f32>(0.0, 0.0, 0.0, 1.0); }

    var t0 = (base - origin.y) / dir.y;
    if (t0 < 0.0) { t0 = 0.0; }
    let t1 = (base + thick - origin.y) / dir.y;
    if (t1 <= 0.0 || t0 > 6000.0) { return vec4<f32>(0.0, 0.0, 0.0, 1.0); }
    let t_end = min(t1, t0 + 6000.0);
    if (t_end <= t0) { return vec4<f32>(0.0, 0.0, 0.0, 1.0); }

    let steps = 20;
    let step_len = (t_end - t0) / f32(steps);
    let jitter = mu_hash3(dir * 811.0);
    var t = t0 + step_len * jitter;
    var trans = 1.0;
    var scattered = vec3<f32>(0.0);

    for (var i = 0; i < 24; i = i + 1) {
        if (i >= steps || trans < 0.015) { break; }
        let p = origin + dir * t;
        let density = mu_cloud_density(p, base, thick, coverage);
        if (density > 0.002) {
            let lit = mu_cloud_lighting(p, density, base, thick, coverage);
            let extinction = density * 0.13 * step_len;
            let sample_trans = exp(-extinction);
            scattered = scattered + trans * (1.0 - sample_trans) * lit;
            trans = trans * sample_trans;
        }
        t = t + step_len;
    }

    let horizon = smoothstep(0.005, 0.08, dir.y);
    let fade = exp(-t0 * 0.00035) * horizon;
    return vec4<f32>(scattered * fade, mix(1.0, trans, fade));
}

// The whole Overworld sky as display-encoded colour. The sky stage always draws
// it in full: with [sky] clouds/sun/stars = false the engine's own sky props are
// gone, so this is the only place they can come from.
fn mu_sky_encoded(dir: vec3<f32>, full: bool) -> vec3<f32> {
    var radiance = mu_sky_radiance(dir, 12) * sky_intensity;

    // the reference's atmosphere reads much bluer than a straight Rayleigh integral;
    // a small saturation boost gets the deep zenith without a LUT.
    let sky_luma = mu_luma709(radiance);
    radiance = mix(vec3<f32>(sky_luma), radiance, sky_saturation);

    let overcast = mu_sat(frame.rain * 0.8 + frame.thunder * 0.2);
    let grey = vec3<f32>(mu_luma709(radiance)) * vec3<f32>(0.85, 0.9, 1.0);
    radiance = mix(radiance, grey * 0.55, overcast);

    // A little extra blue in the upper dome. A pure Rayleigh integral reads
    // grey-blue on a display; this is the "clear day" lift.
    let daylight = smoothstep(-0.10, 0.15, frame.sun_direction.y);
    radiance = radiance + vec3<f32>(0.020, 0.055, 0.150) * daylight * (0.35 + 0.65 * mu_sat(dir.y)) * (1.0 - overcast);

    if (full) {
        let sun = frame.sun_direction;
        let moon = frame.moon_direction;
        let clear = 1.0 - overcast;

        // Sun disc. The moon's disc is still drawn by the engine (there is no
        // manifest flag for it), so only its halo is added here.
        let sun_ang = acos(clamp(dot(dir, sun), -1.0, 1.0));
        let sun_disk = 1.0 - smoothstep(0.0180, 0.0220, sun_ang);
        radiance = radiance + mu_sun_color(sun.y) * (sun_disk * 9.0 * clear);
        // A sun-space halo, so part of the glare is anchored to the sun's
        // direction and cannot drift with a cloud passing under it.
        let sun_mu = mu_sat(dot(dir, sun));
        radiance = radiance + mu_sun_color(sun.y)
            * (pow(sun_mu, 512.0) * 1.10 + pow(sun_mu, 64.0) * 0.12)
            * clear * daylight;
        let moon_ang = acos(clamp(dot(dir, moon), -1.0, 1.0));
        let moon_halo = exp(-moon_ang * 18.0) * 0.22 + exp(-moon_ang * 90.0) * 0.55;
        radiance = radiance + vec3<f32>(0.55, 0.66, 0.95) * (moon_halo * clear * smoothstep(-0.05, 0.1, moon.y));

        // Stars.
        let night = 1.0 - smoothstep(-0.18, 0.0, sun.y);
        if (night > 0.0 && dir.y > 0.02) {
            let cell = floor(dir * 600.0);
            let h = mu_hash3(cell);
            let star = step(0.9965, h);
            let b = 0.5 + 1.2 * mu_hash3(cell + vec3<f32>(7.0, 3.0, 1.0));
            radiance = radiance + vec3<f32>(0.9, 0.95, 1.0) * (star * b * 1.0 * night * clear * smoothstep(0.02, 0.25, dir.y));
        }

        if (clouds_enabled) {
            let cl = mu_clouds(dir);
            radiance = radiance * cl.w + cl.xyz;
        }
    }

    var encoded = mu_scene_encode(radiance);
    // Dither before the 8-bit frame stores the sky: a smooth gradient over a
    // whole dome is exactly where banding shows.
    let dith = (mu_hash3(floor(dir * 4096.0)) - 0.5) / 255.0;
    encoded = clamp(encoded + vec3<f32>(dith), vec3<f32>(0.0), vec3<f32>(1.0));
    // Only the last few degrees above the horizon take the vanilla fog colour,
    // and with a curve that leaves the deep blue overhead alone.
    let edge = 1.0 - smoothstep(0.0, 0.30, dir.y);
    encoded = mix(encoded, frame.fog_color, edge * edge * sky_fog_blend);
    encoded = mix(encoded, frame.fog_color, (1.0 - smoothstep(-0.08, 0.0, dir.y)) * sky_fog_blend * 0.7);
    return encoded;
}
