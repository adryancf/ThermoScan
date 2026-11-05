import sys
import serial
import numpy as np
import matplotlib.pyplot as plt

porta = sys.argv[1] if len(sys.argv) > 1 else "/dev/ttyUSB0"

with serial.Serial(porta, 115200, timeout=3) as esp:
    fig, ax = plt.subplots()
    imagem = ax.imshow(
        np.zeros((32, 24)),
        cmap="inferno",
        vmin=20,
        vmax=45,
        interpolation="bilinear",
    )
    fig.colorbar(imagem, ax=ax, label="Temperatura (°C)")
    ax.set_title("MLX90640 — aguardando quadro")
    plt.show(block=False)

    while plt.fignum_exists(fig.number):
        linha = esp.readline().decode("utf-8", errors="ignore").strip()
        if not linha.startswith("FRAME,"):
            continue

        try:
            valores = np.array(
                [float(x) for x in linha.split(",")[1:]],
                dtype=float,
            )
        except ValueError:
            continue

        if valores.size != 768 or not np.all(np.isfinite(valores)):
            continue

        imagem.set_data(np.rot90(valores.reshape(24, 32)))
        ax.set_title(
            f"MLX90640 — mín {valores.min():.1f} °C | "
            f"máx {valores.max():.1f} °C"
        )
        fig.canvas.draw_idle()
        plt.pause(0.01)