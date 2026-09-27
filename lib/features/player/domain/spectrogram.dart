// lib/features/player/domain/spectrogram.dart
//
// Спектр трека: настоящие частоты, а не одна громкость.
//
// Звук раскладывается по полосам (низы → верха) кадр за кадром и хранится
// как байты: [полос × кадров], по байту на значение. У трёхминутного трека
// при 16 полосах и 25 кадрах в секунду это ~72 КБ.
//
// Откуда берётся PCM — `data/pcm_decoder.dart` (на Windows это libmpv,
// который и так едет с media_kit). Здесь только математика, без платформ,
// поэтому всё покрыто тестами.

import 'dart:math' as math;
import 'dart:typed_data';

/// Сколько полос показываем и как часто.
const kSpectrumBands = 16;
const kSpectrumFps = 25;

/// Окно FFT: 1024 отсчёта при 22050 Гц — это 46 мс, хватает и для низов.
const kFftSize = 1024;

/// Магнитуду FFT надо привести к обычной амплитуде (−1..1), иначе децибелы
/// уходят далеко в плюс и всё обрезается по нулю. У окна Ханна сумма весов
/// равна N/2, а синус даёт половину в каждую сторону: делитель N/4.
const _magnitudeScale = 4 / kFftSize;

/// Готовый спектр: [values] — кадры подряд, в каждом [bands] значений 0..255.
class Spectrogram {
  const Spectrogram({
    required this.values,
    required this.bands,
    required this.frameMs,
  });

  final Uint8List values;
  final int bands;
  final double frameMs;

  int get frames => bands == 0 ? 0 : values.length ~/ bands;

  bool get isEmpty => frames == 0;

  int get durationMs => (frames * frameMs).round();

  /// Полосы в момент [ms] — от низов к верхам, значения 0..1.
  /// Между кадрами сглаживаем, иначе на 25 кадрах видно ступеньки.
  void sampleInto(List<double> out, int ms) {
    if (isEmpty || out.length < bands) return;
    final exact = (ms / frameMs).clamp(0, (frames - 1).toDouble());
    final i = exact.floor();
    final next = math.min(i + 1, frames - 1);
    final t = exact - i;
    for (var b = 0; b < bands; b++) {
      final a = values[i * bands + b] / 255.0;
      final c = values[next * bands + b] / 255.0;
      out[b] = a + (c - a) * t;
    }
  }

  /// Насколько низы подскочили к моменту [ms] — по этому «бьёт» картинка.
  double punchAt(int ms) {
    if (isEmpty) return 0;
    final i = (ms / frameMs).floor().clamp(0, frames - 1);
    final back = math.max(1, (120 / frameMs).round());
    final from = math.max(0, i - back);
    if (i <= from) return 0;

    // Низы — первые четверть полос: бочка живёт там
    final lowBands = math.max(1, bands ~/ 4);
    double energyAt(int frame) {
      var sum = 0;
      for (var b = 0; b < lowBands; b++) {
        sum += values[frame * bands + b];
      }
      return sum / lowBands / 255.0;
    }

    var average = 0.0;
    for (var f = from; f < i; f++) {
      average += energyAt(f);
    }
    average /= (i - from);
    return ((energyAt(i) - average) * 3.5).clamp(0.0, 1.0);
  }
}

/// PCM (моно, [sampleRate] Гц, значения −1..1) → спектр по полосам.
///
/// Отсчёты — `Float32List`: у десятиминутного трека это 53 МБ против 106 МБ,
/// а точности для картинки хватает с запасом.
Spectrogram analyzeSpectrum(
  Float32List samples, {
  required int sampleRate,
  int bands = kSpectrumBands,
  int fps = kSpectrumFps,
}) {
  if (samples.isEmpty || sampleRate <= 0) {
    return Spectrogram(values: Uint8List(0), bands: bands, frameMs: 1000 / fps);
  }

  final hop = math.max(1, sampleRate ~/ fps);
  final frames = math.max(1, (samples.length - kFftSize) ~/ hop + 1);
  final edges = _bandEdges(bands, sampleRate);
  final window = _hann(kFftSize);

  final real = Float64List(kFftSize);
  final imag = Float64List(kFftSize);
  final raw = Float64List(frames * bands);

  for (var f = 0; f < frames; f++) {
    final start = f * hop;
    for (var i = 0; i < kFftSize; i++) {
      final index = start + i;
      real[i] = index < samples.length ? samples[index] * window[i] : 0.0;
      imag[i] = 0.0;
    }
    _fft(real, imag);

    for (var b = 0; b < bands; b++) {
      var sum = 0.0;
      var count = 0;
      for (var k = edges[b]; k < edges[b + 1]; k++) {
        final re = real[k];
        final im = imag[k];
        sum += math.sqrt(re * re + im * im);
        count++;
      }
      raw[f * bands + b] = count == 0 ? 0.0 : sum / count * _magnitudeScale;
    }
  }

  return Spectrogram(
    values: _normalize(raw, frames, bands),
    bands: bands,
    frameMs: 1000 * hop / sampleRate,
  );
}

/// Границы полос по логарифму: низы узкие, верха широкие — как слышит ухо.
List<int> _bandEdges(int bands, int sampleRate) {
  const lowHz = 40.0;
  final highHz = math.min(11000.0, sampleRate / 2 - 100);
  final edges = <int>[];
  for (var b = 0; b <= bands; b++) {
    final hz = lowHz * math.pow(highHz / lowHz, b / bands);
    final bin = (hz * kFftSize / sampleRate).round().clamp(1, kFftSize ~/ 2 - 1);
    edges.add(bin <= (edges.isEmpty ? 0 : edges.last) ? edges.last + 1 : bin);
  }
  return edges;
}

Float64List _hann(int size) {
  final w = Float64List(size);
  for (var i = 0; i < size; i++) {
    w[i] = 0.5 - 0.5 * math.cos(2 * math.pi * i / (size - 1));
  }
  return w;
}

/// Значения → байты.
///
/// Сначала в децибелы: ухо слышит логарифмом, и без этого на картинке жили бы
/// только низы. Дальше — самое важное решение во всём файле.
///
/// **Каждая полоса нормируется по своему размаху.** В музыке энергия падает
/// с частотой: низы громче верхов на 30–40 дБ. Если мерить все полосы одной
/// линейкой, получается горка от низов к верхам, у которой верхние столбики
/// просто лежат, а каждый столбик гуляет лишь по середине своей высоты —
/// проверено на медиатеке, среднее 0,55 при потолке 1,0. Живым это не
/// выглядит. Поэтому у полосы своя верхушка (её же громкое место) и свой пол,
/// и каждая использует высоту целиком.
///
/// Цена честности: картинка показывает **не абсолютную громкость**, а
/// «насколько громко для этой полосы». Тихую песню видно так же хорошо, как
/// громкую. Для визуализатора это то, что нужно, но по нему нельзя судить,
/// сколько в треке баса.
///
/// Чтобы это не превратилось в оживление тишины, есть две защиты: полоса,
/// которая и в громких местах тише −58 дБ, гасится совсем (у трека просто нет
/// таких частот), а пол не ближе 20 дБ к верхушке — иначе ровная полоса
/// растянулась бы на весь экран из шума.
Uint8List _normalize(Float64List raw, int frames, int bands) {
  const silenceDb = -70.0;
  const deadBandDb = -58.0;
  const minRangeDb = 20.0;
  const maxRangeDb = 45.0;

  final out = Uint8List(frames * bands);
  final column = Float64List(frames);

  for (var b = 0; b < bands; b++) {
    for (var f = 0; f < frames; f++) {
      final v = raw[f * bands + b];
      column[f] = v <= 1e-7
          ? silenceDb
          : (20 * math.log(v) / math.ln10).clamp(silenceDb, 0.0);
    }

    final sorted = Float64List.fromList(column)..sort();
    double at(double p) =>
        sorted[(frames * p).floor().clamp(0, frames - 1)];

    final top = at(0.95);
    if (top <= deadBandDb) continue; // таких частот в треке нет
    final floor = at(0.10).clamp(top - maxRangeDb, top - minRangeDb);
    final span = top - floor;

    for (var f = 0; f < frames; f++) {
      // Тишина остаётся тишиной
      if (column[f] <= silenceDb + 0.5) continue;
      final value = ((column[f] - floor) / span).clamp(0.0, 1.0);
      out[f * bands + b] = (value * 255).round();
    }
  }
  return out;
}

/// Обычное быстрое преобразование Фурье, на месте. Размер — степень двойки.
void _fft(Float64List real, Float64List imag) {
  final n = real.length;
  if (n <= 1) return;

  // Перестановка по обратным битам
  var j = 0;
  for (var i = 1; i < n; i++) {
    var bit = n >> 1;
    for (; j & bit != 0; bit >>= 1) {
      j ^= bit;
    }
    j ^= bit;
    if (i < j) {
      final tr = real[i];
      real[i] = real[j];
      real[j] = tr;
      final ti = imag[i];
      imag[i] = imag[j];
      imag[j] = ti;
    }
  }

  for (var len = 2; len <= n; len <<= 1) {
    final angle = -2 * math.pi / len;
    final wr = math.cos(angle);
    final wi = math.sin(angle);
    for (var i = 0; i < n; i += len) {
      var curR = 1.0;
      var curI = 0.0;
      for (var k = 0; k < len ~/ 2; k++) {
        final ar = real[i + k];
        final ai = imag[i + k];
        final br = real[i + k + len ~/ 2];
        final bi = imag[i + k + len ~/ 2];
        final tr = br * curR - bi * curI;
        final ti = br * curI + bi * curR;
        real[i + k] = ar + tr;
        imag[i + k] = ai + ti;
        real[i + k + len ~/ 2] = ar - tr;
        imag[i + k + len ~/ 2] = ai - ti;
        final nextR = curR * wr - curI * wi;
        curI = curR * wi + curI * wr;
        curR = nextR;
      }
    }
  }
}
