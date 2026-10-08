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
/// Удобно для тестов и коротких отрывков; трек целиком считается кусками через
/// [SpectrumAnalyzer], без массива на весь трек в памяти.
Spectrogram analyzeSpectrum(
  Float32List samples, {
  required int sampleRate,
  int bands = kSpectrumBands,
  int fps = kSpectrumFps,
}) {
  if (sampleRate <= 0) {
    return Spectrogram(values: Uint8List(0), bands: bands, frameMs: 1000 / fps);
  }
  return (SpectrumAnalyzer(sampleRate: sampleRate, bands: bands, fps: fps)
        ..add(samples))
      .finish();
}

/// Спектр, который считается по мере чтения звука.
///
/// Зачем кусками. Раньше трек раскодировался в один массив отсчётов, и для
/// двухчасового сборника это было около 640 МБ `Float32List` плюс 320 МБ WAV,
/// прочитанного в память целиком, — на телефоне легко поймать вылет. Теперь
/// в памяти только хвост на одно окно FFT и значения полос: на два часа
/// ~11 МБ. Результат тот же, что у прохода по всему массиву сразу.
class SpectrumAnalyzer {
  SpectrumAnalyzer({
    required this.sampleRate,
    this.bands = kSpectrumBands,
    this.fps = kSpectrumFps,
  })  : _hop = math.max(1, sampleRate ~/ fps),
        _edges = _bandEdges(bands, sampleRate),
        _window = _hann(kFftSize);

  final int sampleRate;
  final int bands;
  final int fps;

  final int _hop;
  final List<int> _edges;
  final Float64List _window;
  final _real = Float64List(kFftSize);
  final _imag = Float64List(kFftSize);

  /// Отсчёты, которые ещё понадобятся: от начала следующего окна до конца
  /// прочитанного.
  Float32List _tail = Float32List(0);

  /// Сколько отсчётов уже отброшено до [_tail].
  int _dropped = 0;

  /// С какого отсчёта начинается следующее окно.
  int _nextStart = 0;

  int _total = 0;
  int _frames = 0;
  Float32List _raw = Float32List(0);

  void add(Float32List samples) {
    if (samples.isEmpty) return;
    _total += samples.length;

    final data = Float32List(_tail.length + samples.length)
      ..setAll(0, _tail)
      ..setAll(_tail.length, samples);

    while (_nextStart + kFftSize <= _dropped + data.length) {
      _frame(data, _nextStart - _dropped);
      _nextStart += _hop;
    }

    final keepFrom = math.min(_nextStart - _dropped, data.length);
    _tail = Float32List.sublistView(data, keepFrom);
    _dropped += keepFrom;
  }

  Spectrogram finish() {
    // Короче одного окна — одно окно, добитое тишиной, как и раньше
    if (_frames == 0 && _total > 0) {
      _frame(_tail, 0);
    }
    if (_frames == 0) {
      return Spectrogram(
          values: Uint8List(0), bands: bands, frameMs: 1000 / fps);
    }
    return Spectrogram(
      values: _normalize(_raw, _frames, bands),
      bands: bands,
      frameMs: 1000 * _hop / sampleRate,
    );
  }

  void _frame(Float32List data, int start) {
    for (var i = 0; i < kFftSize; i++) {
      final index = start + i;
      _real[i] = index < data.length ? data[index] * _window[i] : 0.0;
      _imag[i] = 0.0;
    }
    _fft(_real, _imag);

    if ((_frames + 1) * bands > _raw.length) {
      final grown = Float32List(math.max(bands * 1024, _raw.length * 2))
        ..setAll(0, _raw);
      _raw = grown;
    }
    for (var b = 0; b < bands; b++) {
      var sum = 0.0;
      var count = 0;
      for (var k = _edges[b]; k < _edges[b + 1]; k++) {
        final re = _real[k];
        final im = _imag[k];
        sum += math.sqrt(re * re + im * im);
        count++;
      }
      _raw[_frames * bands + b] =
          count == 0 ? 0.0 : sum / count * _magnitudeScale;
    }
    _frames++;
  }
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
Uint8List _normalize(Float32List raw, int frames, int bands) {
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
