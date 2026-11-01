"""Makes the Standard look: Apple Log (Rec.2020) to normal-looking Rec.709 for phone screens.

The app shows clips through it while filming and reviewing, and the editor uses the same file, so the
preview and the edit start from the same place. Writes ShotGuide/Resources/Standard.cube.

Apple Log curve: Apple Log Profile White Paper (2023), as implemented in colour-science.
"""
import os
import numpy as np

N = 33
R0, RT, SIGMA, BETA, GAMMA, DELTA = -0.05641088, 0.01, 47.28711236, 0.00964052, 0.08550479, 0.69336945
PT = SIGMA * (RT - R0) ** 2
EXPOSURE = 0.75  # puts 18% grey at about 0.47 on screen, like the normal camera

REC2020_TO_REC709 = np.array([
    [1.660491, -0.587641, -0.072850],
    [-0.124550, 1.132900, -0.008349],
    [-0.018151, -0.100579, 1.118730],
])


def apple_log_decode(p):
    p = np.asarray(p, dtype=np.float64)
    return np.where(p >= PT, 2 ** ((p - DELTA) / GAMMA) - BETA,
                    np.where(p >= 0, np.sqrt(np.maximum(p, 0) / SIGMA) + R0, R0))


def filmic(x):
    # A smooth highlight roll-off (Narkowicz's fit of the ACES curve).
    x = np.maximum(x, 0)
    return np.clip((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), 0, 1)


def srgb_encode(linear):
    return np.where(linear <= 0.0031308, 12.92 * linear, 1.055 * np.power(linear, 1 / 2.4) - 0.055)


def standard_look(rgb):
    linear2020 = apple_log_decode(rgb)
    linear709 = linear2020 @ REC2020_TO_REC709.T
    # Colours outside Rec.709 are pulled toward their own brightness rather than clipped hard.
    luma = linear709 @ np.array([0.2126, 0.7152, 0.0722])
    low = np.minimum(linear709.min(axis=-1), 0)
    k = np.where(low < 0, luma / np.maximum(luma - low, 1e-6), 1.0)
    linear709 = luma[..., None] + (linear709 - luma[..., None]) * np.clip(k, 0, 1)[..., None]
    return np.clip(srgb_encode(filmic(linear709 * EXPOSURE)), 0, 1)


def main():
    grid = np.linspace(0, 1, N)
    b, g, r = np.meshgrid(grid, grid, grid, indexing='ij')  # red changes fastest, as .cube files list it
    rgb = np.stack([r, g, b], axis=-1).reshape(-1, 3)
    out = standard_look(rgb)
    here = os.path.dirname(os.path.abspath(__file__))
    path = os.path.join(here, '..', 'ShotGuide', 'Resources', 'Standard.cube')
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w') as f:
        f.write('TITLE "Shot Guide Standard (Apple Log to Rec.709)"\n')
        f.write(f'LUT_3D_SIZE {N}\n')
        f.write('DOMAIN_MIN 0.0 0.0 0.0\nDOMAIN_MAX 1.0 1.0 1.0\n')
        for v in out:
            f.write(f'{v[0]:.6f} {v[1]:.6f} {v[2]:.6f}\n')
    grey = standard_look(np.array([[0.4883, 0.4883, 0.4883]]))[0][0]
    white = standard_look(np.array([[0.6817, 0.6817, 0.6817]]))[0][0]
    print(f'wrote {os.path.normpath(path)}: 18% grey -> {grey:.3f}, 90% white -> {white:.3f}')


if __name__ == '__main__':
    main()
