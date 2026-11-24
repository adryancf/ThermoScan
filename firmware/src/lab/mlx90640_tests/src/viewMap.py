import sys
import time
import serial
import numpy as np
import matplotlib.pyplot as plt
from matplotlib.widgets import Slider, Button

porta = sys.argv[1] if len(sys.argv) > 1 else "/dev/ttyUSB0"

with serial.Serial(porta, 115200, timeout=1) as esp:
    print(f"Conectado a {porta}. Aguardando inicialização da ESP32...")
    time.sleep(2.0)
    esp.reset_input_buffer()
    esp.write(b"diag mlx stream\n")
    print("Comando 'diag mlx stream' enviado. Abrindo assistente de alinhamento + Tilt...")

    fig, (ax_img, ax_prof) = plt.subplots(
        1,
        2,
        figsize=(9.8, 6.8),
        gridspec_kw={"width_ratios": [1.5, 1.0]},
    )
    plt.subplots_adjust(bottom=0.20, top=0.86, wspace=0.32)

    imagem = ax_img.imshow(
        np.zeros((32, 24)),
        cmap="inferno",
        vmin=20,
        vmax=45,
        interpolation="nearest",
        aspect="equal",
    )
    fig.colorbar(imagem, ax=ax_img, label="Temperatura (°C)", fraction=0.046)

    # Guias visuais de alinhamento (mesma orientação 24x32 do app)
    ax_img.axhline(15.5, color="cyan", linestyle="--", linewidth=1.2, alpha=0.85, label="Centro Y")
    ax_img.axvline(11.5, color="white", linestyle=":", linewidth=1.0, alpha=0.65)
    ax_img.axhline(1.5, color="lime", linestyle="--", linewidth=1.0, alpha=0.75, label="Margem ideal")
    ax_img.axhline(29.5, color="lime", linestyle="--", linewidth=1.0, alpha=0.75)
    ax_img.set_xlabel("Eixo do trilho (24 px = 75° | Esq: -X → Dir: +X)")
    ax_img.set_ylabel("Transversal ao painel (32 px = 110°)")
    ax_img.legend(loc="upper right", fontsize=8)

    y_axis = np.arange(32)
    (linha_prof,) = ax_prof.plot(np.zeros(32), y_axis, color="orangered", linewidth=2.0)
    linha_limiar = ax_prof.axvline(30.0, color="gray", linestyle=":", linewidth=1.0)
    ax_prof.axhline(15.5, color="cyan", linestyle="--", linewidth=1.0, alpha=0.7)
    ax_prof.set_ylim(31.5, -0.5)
    ax_prof.set_xlabel("Temp. média na faixa central (°C)")
    ax_prof.set_ylabel("Linha Y (sensorCol 0..31)")
    ax_prof.grid(True, alpha=0.3)
    ax_prof.set_title("Perfil Vertical do Painel")

    # Controle interativo de Tilt do servo da câmera (0° a 180°)
    ax_slider = fig.add_axes([0.16, 0.07, 0.56, 0.045])
    tilt_slider = Slider(
        ax=ax_slider,
        label="Tilt (°)",
        valmin=0.0,
        valmax=180.0,
        valinit=90.0,
        valstep=1.0,
        color="#0B4F6C",
    )
    ax_minus = fig.add_axes([0.75, 0.07, 0.08, 0.045])
    ax_plus = fig.add_axes([0.85, 0.07, 0.08, 0.045])
    btn_minus = Button(ax_minus, "-1°")
    btn_plus = Button(ax_plus, "+1°")

    current_tilt = [90.0]
    suppress_send = [False]

    def send_tilt(angle: float):
        clamped = max(0.0, min(180.0, round(float(angle), 1)))
        current_tilt[0] = clamped
        if suppress_send[0]:
            return
        try:
            esp.write(f"T{clamped:.1f}\n".encode("utf-8"))
        except Exception:
            pass

    tilt_slider.on_changed(send_tilt)
    btn_minus.on_clicked(lambda _: tilt_slider.set_val(max(0.0, tilt_slider.val - 1.0)))
    btn_plus.on_clicked(lambda _: tilt_slider.set_val(min(180.0, tilt_slider.val + 1.0)))

    def on_key(event):
        if event.key in ("up", "right"):
            tilt_slider.set_val(min(180.0, tilt_slider.val + 1.0))
        elif event.key in ("down", "left"):
            tilt_slider.set_val(max(0.0, tilt_slider.val - 1.0))
        elif event.key == "pageup":
            tilt_slider.set_val(min(180.0, tilt_slider.val + 5.0))
        elif event.key == "pagedown":
            tilt_slider.set_val(max(0.0, tilt_slider.val - 5.0))

    fig.canvas.mpl_connect("key_press_event", on_key)

    fig.suptitle("MLX90640 — aguardando quadro... (use o slider ou ↑/↓ para ajustar Tilt)", fontsize=10.5, fontweight="bold")
    plt.show(block=False)

    last_retry = time.time()
    while plt.fignum_exists(fig.number):
        linha = esp.readline().decode("utf-8", errors="ignore").strip()
        if linha.startswith("TILT,"):
            try:
                reported = float(linha.split(",", 1)[1])
                current_tilt[0] = reported
                suppress_send[0] = True
                tilt_slider.set_val(max(0.0, min(180.0, round(reported))))
                suppress_send[0] = False
            except ValueError:
                pass
            continue

        if not linha.startswith("FRAME,"):
            if time.time() - last_retry > 2.5:
                esp.write(b"diag mlx stream\n")
                last_retry = time.time()
            plt.pause(0.01)
            continue

        last_retry = time.time()
        try:
            valores = np.array(
                [float(x) for x in linha.split(",")[1:]],
                dtype=float,
            )
        except ValueError:
            continue

        if valores.size != 768 or not np.all(np.isfinite(valores)):
            continue

        # Mesma orientação 24x32 do app:
        # sensorRow (0..23) na horizontal (X do trilho) e sensorCol (0..31) na vertical (Y do painel)
        matriz = valores.reshape(24, 32).T  # shape (32, 24)
        vmin = float(matriz.min())
        vmax = float(matriz.max())
        span = max(vmax - vmin, 4.0)

        imagem.set_data(matriz)
        imagem.set_clim(vmin=vmin, vmax=vmin + span)

        # Perfil vertical usando as 6 colunas centrais do trilho (rows 9..14)
        perfil_y = matriz[:, 9:15].mean(axis=1)
        p_min = float(perfil_y.min())
        p_max = float(perfil_y.max())
        limiar = p_min + 0.4 * (p_max - p_min)
        quentes = np.where(perfil_y >= limiar)[0]

        linha_prof.set_xdata(perfil_y)
        linha_limiar.set_xdata([limiar, limiar])
        ax_prof.set_xlim(p_min - 1.0, p_max + 1.5)

        if (p_max - p_min) < 2.5 or quentes.size == 0:
            status = "Aqueça o painel (ou passe a mão nas bordas) para ver o contraste"
        else:
            y_top = int(quentes[0])
            y_bot = int(quentes[-1])
            centro = 0.5 * (y_top + y_bot)
            cobertura_pct = (quentes.size / 32.0) * 100.0
            erro = centro - 15.5

            if abs(erro) <= 2.0:
                dir_msg = "CENTRALIZADO ✓"
            elif erro > 2.0:
                dir_msg = f"PAINEL EMBAIXO (Y={y_top}..{y_bot}) → ajuste o Tilt"
            else:
                dir_msg = f"PAINEL EM CIMA (Y={y_top}..{y_bot}) → ajuste o Tilt"

            if cobertura_pct < 65:
                dist_msg = "aproxime a câmera"
            elif cobertura_pct > 95:
                dist_msg = "afaste um pouco"
            else:
                dist_msg = "altura OK ✓"

            status = f"{dir_msg} | Cobertura: {cobertura_pct:.0f}% ({dist_msg})"

        fig.suptitle(
            f"MLX90640 | Tilt atual: {current_tilt[0]:.0f}° | Mín: {vmin:.1f}°C · Máx: {vmax:.1f}°C\n{status}",
            fontsize=10.5,
            fontweight="bold",
        )
        fig.canvas.draw_idle()
        plt.pause(0.01)

    try:
        esp.write(b"q\n")
    except Exception:
        pass
