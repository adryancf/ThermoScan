import sys
from datetime import datetime

import matplotlib.pyplot as plt
import numpy as np
import serial

porta = sys.argv[1] if len(sys.argv) > 1 else "/dev/ttyUSB0"

print("Aponte a câmera para a cena e pressione Enter para capturar.")
input()

with serial.Serial(porta, 115200, timeout=3) as esp:
    # Abrir a porta pode reiniciar o ESP32; descarta linhas incompletas.
    matriz = None
    while matriz is None:
        linha = esp.readline().decode("utf-8", errors="ignore").strip()
        if not linha.startswith("FRAME,"):
            continue

        try:
            valores = np.array(
                [float(x) for x in linha.split(",")[1:]], dtype=float
            )
        except ValueError:
            continue

        if valores.size != 768 or not np.all(np.isfinite(valores)):
            continue

        matriz = np.rot90(valores.reshape(24, 32))

momento = datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
nome = f"matriz_termica_{momento}.png"

fig, ax = plt.subplots(figsize=(15, 19), layout="constrained")
im = ax.imshow(
    matriz,
    cmap="inferno",
    vmin=20,
    vmax=60,
    interpolation="nearest",
    origin="lower",
)

# Escreve a temperatura medida no centro de cada célula.
for y in range(32):
    for x in range(24):
        temperatura = matriz[y, x]
        cor = "black" if im.norm(temperatura) > 0.72 else "white"
        ax.text(
            x, y, f"{temperatura:.1f}",
            ha="center", va="center",
            fontsize=5, color=cor,
        )

y_max, x_max = np.unravel_index(np.argmax(matriz), matriz.shape)
ax.plot(x_max, y_max, "o", markerfacecolor="none",
        markeredgecolor="cyan", markersize=17, markeredgewidth=2)

ax.set_title(
    f"MLX90640 — matriz térmica medida (32 × 24)\n"
    f"{momento} | mín. {matriz.min():.1f} °C | "
    f"máx. {matriz.max():.1f} °C",
    fontsize=15,
)
ax.set_xlabel("X — 24 posições")
ax.set_ylabel("Y — 32 posições")
ax.set_xticks(range(0, 24, 2))
ax.set_yticks(range(0, 32, 2))
fig.colorbar(im, ax=ax, label="Temperatura (°C)", shrink=0.75)

fig.savefig(nome, dpi=200, bbox_inches="tight")
plt.close(fig)
print(f"Imagem salva: {nome}")