import numpy as np
import matplotlib.pyplot as plt
import csv
from pathlib import Path
from tkinter import Tk, filedialog
from scipy.optimize import minimize_scalar


# ============================================================
#          TGG 未知交流频率自动分析程序
# ============================================================
#
# 处理流程：
#
# LabVIEW CSV
#      ↓
# 电压 V(t)
#      ↓
# theta(t) = arcsin(sqrt(V(t) / Vmax))
#      ↓
# 去除静态偏置
#      ↓
# FFT
#      ↓
# 在指定频率范围内自动寻找最大主峰
#      ↓
# FFT 三点抛物线插值
#      ↓
# 正弦最小二乘拟合
#      ↓
# 得到更精细的实际频率估计
#
# 频率：保留 4 位小数
# 振幅：保留 8 位小数
#
# ============================================================


# ============================================================
# 1. 选择 LabVIEW CSV 文件
# ============================================================

root = Tk()
root.withdraw()

file_path = filedialog.askopenfilename(
    title="请选择 LabVIEW 导出的 CSV 文件",
    filetypes=[
        ("CSV 文件", "*.csv"),
        ("文本文件", "*.txt"),
        ("所有文件", "*.*")
    ]
)

root.destroy()

if not file_path:
    print("没有选择文件，程序结束。")
    exit()

file_path = Path(file_path)

print("\n========================================")
print("已选择文件")
print("========================================")
print(file_path)


# ============================================================
# 2. 自动读取 CSV 中的数字
# ============================================================

def read_csv_numeric(path):

    with open(
        path,
        "r",
        encoding="utf-8-sig",
        errors="ignore"
    ) as f:

        sample = f.read(4096)
        f.seek(0)

        # 自动判断分隔符
        try:

            dialect = csv.Sniffer().sniff(
                sample,
                delimiters=",;\t"
            )

            delimiter = dialect.delimiter

        except csv.Error:

            delimiter = ","

        reader = csv.reader(
            f,
            delimiter=delimiter
        )

        rows = []

        for row in reader:

            numeric_row = []

            for value in row:

                try:

                    numeric_row.append(
                        float(value.strip())
                    )

                except:

                    numeric_row.append(
                        np.nan
                    )

            if np.any(
                np.isfinite(numeric_row)
            ):

                rows.append(numeric_row)

    if len(rows) == 0:

        raise ValueError(
            "CSV 中没有找到有效数值。"
        )

    max_columns = max(
        len(row)
        for row in rows
    )

    data = np.full(
        (len(rows), max_columns),
        np.nan
    )

    for i, row in enumerate(rows):

        data[i, :len(row)] = row

    # 删除完全为空的列
    valid_columns = []

    for i in range(data.shape[1]):

        if np.any(
            np.isfinite(data[:, i])
        ):

            valid_columns.append(i)

    data = data[:, valid_columns]

    return data


# ============================================================
# 3. 读取数据
# ============================================================

try:

    data = read_csv_numeric(
        file_path
    )

except Exception as e:

    print("\nCSV读取失败：")
    print(e)
    exit()


print("\n========================================")
print("CSV 数据情况")
print("========================================")

print(
    f"检测到数值列数量：{data.shape[1]}"
)


# ============================================================
# 4. 显示每一列前5个数据
# ============================================================

for i in range(
    data.shape[1]
):

    values = data[:, i]

    values = values[
        np.isfinite(values)
    ]

    print(
        f"\n第 {i + 1} 列前5个数据："
    )

    print(
        values[:5]
    )


# ============================================================
# 5. 选择电压列
# ============================================================

while True:

    try:

        voltage_column = int(
            input(
                "\n请输入电压所在列号（从1开始）："
            )
        ) - 1

        if (
            0
            <= voltage_column
            < data.shape[1]
        ):
            break

        print(
            "列号超出范围，请重新输入。"
        )

    except ValueError:

        print(
            "请输入整数。"
        )


# ============================================================
# 6. CSV 是否有时间列
# ============================================================

has_time = input(
    "\nCSV中是否包含时间列？(y/n)："
).strip().lower()


# ============================================================
# 7. 建立时间轴并得到采样率
# ============================================================

if has_time == "y":

    while True:

        try:

            time_column = int(
                input(
                    "请输入时间所在列号（从1开始）："
                )
            ) - 1

            if (
                0
                <= time_column
                < data.shape[1]
            ):
                break

            print(
                "列号超出范围。"
            )

        except ValueError:

            print(
                "请输入整数。"
            )

    valid = (
        np.isfinite(
            data[:, time_column]
        )
        &
        np.isfinite(
            data[:, voltage_column]
        )
    )

    time = data[
        valid,
        time_column
    ]

    voltage = data[
        valid,
        voltage_column
    ]

    # 时间单位
    time_unit = input(
        "\n时间列单位是什么？"
        " 输入 s、ms 或 us："
    ).strip().lower()

    if time_unit == "ms":

        time = (
            time
            *
            1e-3
        )

    elif time_unit == "us":

        time = (
            time
            *
            1e-6
        )

    elif time_unit == "s":

        pass

    else:

        print(
            "没有识别时间单位，默认按秒处理。"
        )

    dt_array = np.diff(
        time
    )

    dt = np.median(
        dt_array
    )

    if dt <= 0:

        raise ValueError(
            "时间列存在问题，时间间隔必须大于0。"
        )

    fs = (
        1
        /
        dt
    )

    print(
        f"\n自动计算得到采样率 Rate = "
        f"{fs:.4f} Hz"
    )


else:

    voltage = data[
        :,
        voltage_column
    ]

    voltage = voltage[
        np.isfinite(voltage)
    ]

    while True:

        try:

            fs = float(
                input(
                    "\n请输入 LabVIEW 中的 Rate（Hz）："
                )
            )

            if fs > 0:
                break

            print(
                "Rate 必须大于0。"
            )

        except ValueError:

            print(
                "请输入有效数字。"
            )

    # 自动建立时间轴
    time = (
        np.arange(
            len(voltage)
        )
        /
        fs
    )


# ============================================================
# 8. 输入 Vmax
# ============================================================

while True:

    try:

        Vmax = float(
            input(
                "\n请输入实验测得的 Vmax（V）："
            )
        )

        if Vmax > 0:
            break

        print(
            "Vmax 必须大于0。"
        )

    except ValueError:

        print(
            "请输入有效数字。"
        )


# ============================================================
# 9. 输入未知信号的分析范围
# ============================================================

while True:

    try:

        min_frequency = float(
            input(
                "\n请输入最低分析频率（Hz）："
            )
        )

        max_frequency = float(
            input(
                "请输入最高分析频率（Hz）："
            )
        )

        if (
            min_frequency >= 0
            and
            max_frequency > min_frequency
        ):
            break

        print(
            "频率范围输入有误，请重新输入。"
        )

    except ValueError:

        print(
            "请输入有效数字。"
        )


# ============================================================
# 10. 数据基本信息
# ============================================================

N = len(
    voltage
)

total_time = (
    N
    /
    fs
)

frequency_resolution = (
    fs
    /
    N
)

nyquist_frequency = (
    fs
    /
    2
)


print("\n========================================")
print("采集参数")
print("========================================")

print(
    f"采样点数 N = {N}"
)

print(
    f"采样率 Rate = {fs:.4f} Hz"
)

print(
    f"采集时间 T = {total_time:.4f} s"
)

print(
    f"FFT原始频率间隔 Δf = "
    f"{frequency_resolution:.4f} Hz"
)

print(
    f"奈奎斯特频率 = "
    f"{nyquist_frequency:.4f} Hz"
)


# ============================================================
# 11. 检查分析频率范围
# ============================================================

if max_frequency > nyquist_frequency:

    print(
        "\n注意："
    )

    print(
        "最高分析频率超过奈奎斯特频率。"
    )

    print(
        f"程序自动将最高频率改为 "
        f"{nyquist_frequency:.4f} Hz"
    )

    max_frequency = (
        nyquist_frequency
    )


# ============================================================
# 12. TGG 电压 → 角度
#
# theta(t) = arcsin(sqrt(V(t) / Vmax))
#
# ============================================================

ratio = (
    voltage
    /
    Vmax
)


# 检查异常值
too_low = np.sum(
    ratio < 0
)

too_high = np.sum(
    ratio > 1
)


if (
    too_low > 0
    or
    too_high > 0
):

    print("\n========================================")
    print("注意")
    print("========================================")

    print(
        f"V/Vmax < 0 的点数："
        f"{too_low}"
    )

    print(
        f"V/Vmax > 1 的点数："
        f"{too_high}"
    )

    print(
        "程序将这些值限制到0～1范围。"
    )


ratio = np.clip(
    ratio,
    0,
    1
)


theta = np.arcsin(
    np.sqrt(
        ratio
    )
)


# ============================================================
# 13. 去除静态偏置
# ============================================================

theta_mean = np.mean(
    theta
)


theta_ac = (
    theta
    -
    theta_mean
)


print("\n========================================")
print("角度信息")
print("========================================")

print(
    f"平均偏置角 = "
    f"{theta_mean:.8f} rad"
)


# ============================================================
# 14. FFT
# ============================================================

fft_result = np.fft.rfft(
    theta_ac
)


frequency = np.fft.rfftfreq(
    N,
    d=1 / fs
)


amplitude = (
    np.abs(
        fft_result
    )
    /
    N
)


# ============================================================
# 15. 单边 FFT 振幅修正
# ============================================================

if N % 2 == 0:

    amplitude[
        1:-1
    ] *= 2

else:

    amplitude[
        1:
    ] *= 2


# ============================================================
# 16. 在指定频率范围内自动寻找最大峰
# ============================================================

search_mask = (
    (frequency >= min_frequency)
    &
    (frequency <= max_frequency)
)


candidate_indices = np.where(
    search_mask
)[0]


if len(
    candidate_indices
) == 0:

    raise ValueError(
        "指定频率范围内没有FFT数据。"
    )


peak_index = candidate_indices[
    np.argmax(
        amplitude[
            candidate_indices
        ]
    )
]


peak_frequency = (
    frequency[
        peak_index
    ]
)


peak_amplitude = (
    amplitude[
        peak_index
    ]
)


# ============================================================
# 17. FFT 三点抛物线插值
# ============================================================

refined_frequency = (
    peak_frequency
)

refined_amplitude = (
    peak_amplitude
)


if (
    1
    <= peak_index
    <
    len(amplitude) - 1
):

    y1 = amplitude[
        peak_index - 1
    ]

    y2 = amplitude[
        peak_index
    ]

    y3 = amplitude[
        peak_index + 1
    ]


    denominator = (
        y1
        -
        2 * y2
        +
        y3
    )


    if abs(
        denominator
    ) > 1e-20:

        delta = (
            0.5
            *
            (y1 - y3)
            /
            denominator
        )


        delta = np.clip(
            delta,
            -1,
            1
        )


        refined_frequency = (
            peak_frequency
            +
            delta
            *
            frequency_resolution
        )


        refined_amplitude = (
            y2
            -
            0.25
            *
            (y1 - y3)
            *
            delta
        )


# ============================================================
# 18. 正弦拟合
#
# theta(t)
#
# =
#
# a sin(2πft)
# +
# b cos(2πft)
# +
# C
#
# ============================================================

t_fit = (
    time
    -
    time[0]
)


def sine_fit_at_frequency(f):

    omega = (
        2
        *
        np.pi
        *
        f
    )


    X = np.column_stack(
        (

            np.sin(
                omega
                *
                t_fit
            ),

            np.cos(
                omega
                *
                t_fit
            ),

            np.ones_like(
                t_fit
            )

        )
    )


    coefficients, _, _, _ = (
        np.linalg.lstsq(
            X,
            theta,
            rcond=None
        )
    )


    fitted = (
        X
        @
        coefficients
    )


    residual = (
        theta
        -
        fitted
    )


    mse = np.mean(
        residual ** 2
    )


    return (
        mse,
        coefficients,
        fitted
    )


# ============================================================
# 19. FFT 峰附近进一步搜索最佳频率
# ============================================================

fit_min_frequency = max(
    min_frequency,
    refined_frequency
    -
    frequency_resolution
)


fit_max_frequency = min(
    max_frequency,
    refined_frequency
    +
    frequency_resolution
)


def objective(f):

    mse, _, _ = (
        sine_fit_at_frequency(
            f
        )
    )

    return mse


result = minimize_scalar(

    objective,

    bounds=(
        fit_min_frequency,
        fit_max_frequency
    ),

    method="bounded",

    options={
        "xatol": 1e-10
    }

)


fitted_frequency = (
    result.x
)


# ============================================================
# 20. 使用最终频率重新拟合
# ============================================================

mse, coefficients, fitted_theta = (
    sine_fit_at_frequency(
        fitted_frequency
    )
)


a = coefficients[0]

b = coefficients[1]

offset = coefficients[2]


# ============================================================
# 21. 正弦振幅和初相位
# ============================================================

fitted_amplitude = np.sqrt(
    a ** 2
    +
    b ** 2
)


fitted_phase = np.arctan2(
    b,
    a
)


# ============================================================
# 22. 计算拟合质量 R²
# ============================================================

signal_variance = np.var(
    theta
)


if signal_variance > 0:

    r_squared = (
        1
        -
        mse
        /
        signal_variance
    )

else:

    r_squared = 0


# ============================================================
# 23. 输出最终分析结果
#
# 频率：4位小数
# 振幅：8位小数
# ============================================================

print("\n")
print("========================================")
print("            最终频率分析结果")
print("========================================")


print(
    f"分析频率范围       = "
    f"{min_frequency:.4f}"
    f" ~ "
    f"{max_frequency:.4f} Hz"
)


print()


print(
    f"FFT原始频率间隔    = "
    f"{frequency_resolution:.4f} Hz"
)


print(
    f"FFT最大格点频率    = "
    f"{peak_frequency:.4f} Hz"
)


print(
    f"FFT最大格点振幅    = "
    f"{peak_amplitude:.8f} rad"
)


print()


print(
    f"FFT插值频率        = "
    f"{refined_frequency:.4f} Hz"
)


print(
    f"FFT插值振幅        = "
    f"{refined_amplitude:.8f} rad"
)


print()


print(
    "----------------------------------------"
)


print(
    f"最终拟合频率        = "
    f"{fitted_frequency:.4f} Hz"
)


print(
    f"最终拟合角度振幅    = "
    f"{fitted_amplitude:.8f} rad"
)


print(
    f"拟合初相位          = "
    f"{fitted_phase:.8f} rad"
)


print(
    f"拟合平均偏置角      = "
    f"{offset:.8f} rad"
)


print(
    f"拟合 R²             = "
    f"{r_squared:.4f}"
)


print(
    "----------------------------------------"
)


# ============================================================
# 24. 保存全部 FFT 数据
#
# Frequency：4位小数
# Amplitude：8位小数
# ============================================================

fft_output_path = (
    file_path.with_name(

        file_path.stem
        +
        "_FFT_result.csv"

    )
)


with open(

    fft_output_path,

    "w",

    newline="",

    encoding="utf-8-sig"

) as f:


    writer = csv.writer(
        f
    )


    writer.writerow(
        [
            "Frequency (Hz)",
            "Amplitude (rad)"
        ]
    )


    for freq, amp in zip(
        frequency,
        amplitude
    ):


        writer.writerow(
            [
                f"{freq:.4f}",
                f"{amp:.8f}"
            ]
        )


# ============================================================
# 25. 保存最终分析结果
# ============================================================

summary_path = (
    file_path.with_name(

        file_path.stem
        +
        "_Frequency_summary.csv"

    )
)


with open(

    summary_path,

    "w",

    newline="",

    encoding="utf-8-sig"

) as f:


    writer = csv.writer(
        f
    )


    writer.writerow(
        [
            "Parameter",
            "Value"
        ]
    )


    writer.writerow(
        [
            "Minimum analysis frequency (Hz)",
            f"{min_frequency:.4f}"
        ]
    )


    writer.writerow(
        [
            "Maximum analysis frequency (Hz)",
            f"{max_frequency:.4f}"
        ]
    )


    writer.writerow(
        [
            "FFT resolution (Hz)",
            f"{frequency_resolution:.4f}"
        ]
    )


    writer.writerow(
        [
            "FFT peak frequency (Hz)",
            f"{peak_frequency:.4f}"
        ]
    )


    writer.writerow(
        [
            "FFT peak amplitude (rad)",
            f"{peak_amplitude:.8f}"
        ]
    )


    writer.writerow(
        [
            "FFT interpolated frequency (Hz)",
            f"{refined_frequency:.4f}"
        ]
    )


    writer.writerow(
        [
            "FFT interpolated amplitude (rad)",
            f"{refined_amplitude:.8f}"
        ]
    )


    writer.writerow(
        [
            "Final sine-fit frequency (Hz)",
            f"{fitted_frequency:.4f}"
        ]
    )


    writer.writerow(
        [
            "Final sine-fit amplitude (rad)",
            f"{fitted_amplitude:.8f}"
        ]
    )


    writer.writerow(
        [
            "Fitted phase (rad)",
            f"{fitted_phase:.8f}"
        ]
    )


    writer.writerow(
        [
            "Fitted offset angle (rad)",
            f"{offset:.8f}"
        ]
    )


    writer.writerow(
        [
            "R squared",
            f"{r_squared:.4f}"
        ]
    )


print("\n========================================")
print("数据文件已保存")
print("========================================")


print(
    "\n完整FFT数据："
)

print(
    fft_output_path
)


print(
    "\n最终频率分析结果："
)

print(
    summary_path
)


# ============================================================
# 26. 绘制完整 FFT 频谱
# ============================================================

plt.figure(
    figsize=(10, 6)
)


plt.plot(
    frequency,
    amplitude
)


plt.xlabel(
    "Frequency (Hz)"
)


plt.ylabel(
    "Amplitude (rad)"
)


plt.title(
    "TGG FFT Spectrum"
)


plt.grid(
    True
)


plt.tight_layout()


full_fft_path = (
    file_path.with_name(

        file_path.stem
        +
        "_FFT_full.png"

    )
)


plt.savefig(
    full_fft_path,
    dpi=300
)


# ============================================================
# 27. 绘制指定分析区域
# ============================================================

plt.figure(
    figsize=(10, 6)
)


plt.plot(
    frequency,
    amplitude
)


# FFT原始峰值
plt.scatter(
    peak_frequency,
    peak_amplitude,
    s=60,
    label="FFT peak"
)


# 最终拟合频率
plt.axvline(
    fitted_frequency,
    linestyle="--",
    label="Final fitted frequency"
)


plt.xlim(
    min_frequency,
    max_frequency
)


plt.xlabel(
    "Frequency (Hz)"
)


plt.ylabel(
    "Amplitude (rad)"
)


plt.title(
    "TGG FFT - Analysis Range"
)


plt.grid(
    True
)


plt.legend()


result_text = (

    f"FFT peak = "
    f"{peak_frequency:.4f} Hz\n"

    f"FFT interpolation = "
    f"{refined_frequency:.4f} Hz\n"

    f"Final fit = "
    f"{fitted_frequency:.4f} Hz\n"

    f"Amplitude = "
    f"{fitted_amplitude:.8f} rad"

)


plt.text(

    0.98,

    0.95,

    result_text,

    transform=plt.gca().transAxes,

    horizontalalignment="right",

    verticalalignment="top",

    bbox=dict(
        boxstyle="round",
        alpha=0.8
    )

)


plt.tight_layout()


zoom_fft_path = (
    file_path.with_name(

        file_path.stem
        +
        "_FFT_analysis.png"

    )
)


plt.savefig(
    zoom_fft_path,
    dpi=300
)


# ============================================================
# 28. 绘制原始角度和正弦拟合
# ============================================================

plt.figure(
    figsize=(10, 6)
)


plt.plot(
    t_fit,
    theta,
    label="Measured"
)


plt.plot(
    t_fit,
    fitted_theta,
    label="Sine fit"
)


plt.xlabel(
    "Time (s)"
)


plt.ylabel(
    "Angle (rad)"
)


plt.title(
    "TGG Signal and Sine Fit"
)


plt.grid(
    True
)


plt.legend()


fit_text = (

    f"Frequency = "
    f"{fitted_frequency:.4f} Hz\n"

    f"Amplitude = "
    f"{fitted_amplitude:.8f} rad\n"

    f"R² = "
    f"{r_squared:.4f}"

)


plt.text(

    0.98,

    0.95,

    fit_text,

    transform=plt.gca().transAxes,

    horizontalalignment="right",

    verticalalignment="top",

    bbox=dict(
        boxstyle="round",
        alpha=0.8
    )

)


plt.tight_layout()


fit_plot_path = (
    file_path.with_name(

        file_path.stem
        +
        "_Sine_fit.png"

    )
)


plt.savefig(
    fit_plot_path,
    dpi=300
)


# ============================================================
# 29. 显示图片
# ============================================================

plt.show()


print("\n========================================")
print("图片已经保存")
print("========================================")


print(
    full_fft_path
)

print(
    zoom_fft_path
)

print(
    fit_plot_path
)


print("\n========================================")
print("程序运行结束")
print("========================================")