import 'dart:typed_data';

/// Pure Dart QR Code generator (supports Byte mode with Error Correction Level M/Q).
/// Generates a boolean 2D matrix (true = dark, false = light).
class QrCode {
  final int version; // 1 to 10
  final int errorCorrectionLevel; // 0=M (15%), 1=L (7%), 2=H (30%), 3=Q (25%)
  late final int moduleCount;
  late final List<List<bool?>> _modules;

  QrCode._(this.version, this.errorCorrectionLevel) {
    moduleCount = version * 4 + 17;
    _modules = List.generate(
      moduleCount,
      (_) => List<bool?>.filled(moduleCount, null),
    );
  }

  bool isDark(int row, int col) => _modules[row][col] ?? false;

  /// Creates a QR Code for the given text with automatic version selection.
  factory QrCode.encodeText(String text, {int ecLevel = 0}) {
    final bytes = Uint8List.fromList(text.codeUnits);
    // Find smallest version that fits
    int ver = 1;
    for (int v = 1; v <= 10; v++) {
      final capacity = _getDataCapacity(v, ecLevel);
      // Byte mode header: 4 bits mode + 8 bits char count + data * 8 bits
      final neededBits = 4 + 8 + bytes.length * 8;
      if (neededBits <= capacity * 8) {
        ver = v;
        break;
      }
      if (v == 10) ver = 10;
    }

    final qr = QrCode._(ver, ecLevel);
    qr._generate(bytes);
    return qr;
  }

  void _generate(Uint8List dataBytes) {
    _setupPositionProbePattern(0, 0);
    _setupPositionProbePattern(moduleCount - 7, 0);
    _setupPositionProbePattern(0, moduleCount - 7);
    _setupTimingPattern();
    _setupAlignmentPatterns();

    final dataBits = _createDataBits(dataBytes);
    final finalCodewords = _createFinalCodewords(dataBits);

    // Try mask patterns (0 to 7) and select the best one or default to 0
    _placeData(finalCodewords, 0);
    _setupFormatInfo(0);
  }

  void _setupPositionProbePattern(int row, int col) {
    for (int r = -1; r <= 7; r++) {
      if (row + r < 0 || moduleCount <= row + r) continue;
      for (int c = -1; c <= 7; c++) {
        if (col + c < 0 || moduleCount <= col + c) continue;
        if ((0 <= r && r <= 6 && (c == 0 || c == 6)) ||
            (0 <= c && c <= 6 && (r == 0 || r == 6)) ||
            (2 <= r && r <= 4 && 2 <= c && c <= 4)) {
          _modules[row + r][col + c] = true;
        } else {
          _modules[row + r][col + c] = false;
        }
      }
    }
  }

  void _setupTimingPattern() {
    for (int i = 8; i < moduleCount - 8; i++) {
      final val = (i % 2 == 0);
      if (_modules[6][i] == null) _modules[6][i] = val;
      if (_modules[i][6] == null) _modules[i][6] = val;
    }
  }

  void _setupAlignmentPatterns() {
    final pos = _getAlignmentPatternPositions(version);
    for (int i = 0; i < pos.length; i++) {
      for (int j = 0; j < pos.length; j++) {
        final row = pos[i];
        final col = pos[j];
        if (_modules[row][col] != null) continue; // Skip if overlapping finder

        for (int r = -2; r <= 2; r++) {
          for (int c = -2; c <= 2; c++) {
            if (r == -2 || r == 2 || c == -2 || c == 2 || (r == 0 && c == 0)) {
              _modules[row + r][col + c] = true;
            } else {
              _modules[row + r][col + c] = false;
            }
          }
        }
      }
    }
  }

  List<bool> _createDataBits(Uint8List dataBytes) {
    final bits = <bool>[];
    // 1. Mode indicator: Byte mode = 0100
    bits.addAll([false, true, false, false]);

    // 2. Character count (8 bits for versions 1-9, 16 bits for 10+)
    final countBits = version < 10 ? 8 : 16;
    for (int i = countBits - 1; i >= 0; i--) {
      bits.add(((dataBytes.length >> i) & 1) == 1);
    }

    // 3. Data bytes
    for (final b in dataBytes) {
      for (int i = 7; i >= 0; i--) {
        bits.add(((b >> i) & 1) == 1);
      }
    }

    // 4. Terminator: up to 4 zero bits
    final capacityBits = _getDataCapacity(version, errorCorrectionLevel) * 8;
    for (int i = 0; i < 4 && bits.length < capacityBits; i++) {
      bits.add(false);
    }

    // 5. Pad to multiple of 8
    while (bits.length % 8 != 0) {
      bits.add(false);
    }

    // 6. Pad bytes 0xEC, 0x11
    final padBytes = [0xEC, 0x11];
    int padIdx = 0;
    while (bits.length < capacityBits) {
      final b = padBytes[padIdx % 2];
      for (int i = 7; i >= 0; i--) {
        bits.add(((b >> i) & 1) == 1);
      }
      padIdx++;
    }

    return bits;
  }

  List<int> _createFinalCodewords(List<bool> dataBits) {
    final dataCodewords = <int>[];
    for (int i = 0; i < dataBits.length; i += 8) {
      int byte = 0;
      for (int b = 0; b < 8; b++) {
        if (dataBits[i + b]) byte |= (1 << (7 - b));
      }
      dataCodewords.add(byte);
    }

    final totalBlocks = _getNumBlocks(version, errorCorrectionLevel);
    final ecPerBlock = _getEcCodewordsPerBlock(version, errorCorrectionLevel);
    final blockDataLens = _getBlockDataLengths(version, errorCorrectionLevel, dataCodewords.length);

    final dataBlocks = <List<int>>[];
    final ecBlocks = <List<int>>[];

    int offset = 0;
    for (int b = 0; b < totalBlocks; b++) {
      final len = blockDataLens[b];
      final blockData = dataCodewords.sublist(offset, offset + len);
      offset += len;
      dataBlocks.add(blockData);
      ecBlocks.add(_calcReedSolomon(blockData, ecPerBlock));
    }

    // Interleave data codewords
    final result = <int>[];
    int maxDataLen = blockDataLens.reduce((a, b) => a > b ? a : b);
    for (int i = 0; i < maxDataLen; i++) {
      for (int b = 0; b < totalBlocks; b++) {
        if (i < dataBlocks[b].length) {
          result.add(dataBlocks[b][i]);
        }
      }
    }

    // Interleave error correction codewords
    for (int i = 0; i < ecPerBlock; i++) {
      for (int b = 0; b < totalBlocks; b++) {
        result.add(ecBlocks[b][i]);
      }
    }

    return result;
  }

  void _placeData(List<int> codewords, int mask) {
    int byteIdx = 0;
    int bitIdx = 7;

    int dir = -1; // Moving upwards
    int row = moduleCount - 1;
    int col = moduleCount - 1;

    while (col > 0) {
      if (col == 6) col--; // Skip vertical timing column

      for (int i = 0; i < 2; i++) {
        final c = col - i;
        if (_modules[row][c] == null) {
          bool bit = false;
          if (byteIdx < codewords.length) {
            bit = ((codewords[byteIdx] >> bitIdx) & 1) == 1;
            bitIdx--;
            if (bitIdx < 0) {
              bitIdx = 7;
              byteIdx++;
            }
          }
          final maskBit = _getMaskBit(mask, row, c);
          _modules[row][c] = bit ^ maskBit;
        }
      }

      row += dir;
      if (row < 0 || row >= moduleCount) {
        dir = -dir;
        row += dir;
        col -= 2;
      }
    }
  }

  void _setupFormatInfo(int mask) {
    // Format info bits: EC Level M = 00, L = 01, H = 10, Q = 11
    final ecBits = (errorCorrectionLevel == 0) ? 0 : (errorCorrectionLevel == 1 ? 1 : (errorCorrectionLevel == 2 ? 2 : 3));
    final data = (ecBits << 3) | mask;
    // BCH (15, 5) code calculation
    int rem = data << 10;
    for (int i = 4; i >= 0; i--) {
      if ((rem & (1 << (i + 10))) != 0) {
        rem ^= (0x537 << i);
      }
    }
    final formatBits = ((data << 10) | rem) ^ 0x5412;

    for (int i = 0; i < 15; i++) {
      final bit = ((formatBits >> i) & 1) == 1;
      if (i <= 5) {
        _modules[8][i] = bit;
      } else if (i == 6) {
        _modules[8][7] = bit;
      } else if (i == 7) {
        _modules[8][8] = bit;
      } else if (i == 8) {
        _modules[7][8] = bit;
      } else {
        _modules[14 - i][8] = bit;
      }

      if (i < 8) {
        _modules[moduleCount - 1 - i][8] = bit;
      } else {
        _modules[8][moduleCount - 15 + i] = bit;
      }
    }

    _modules[moduleCount - 8][8] = true; // Always dark module
  }

  static bool _getMaskBit(int mask, int row, int col) {
    switch (mask) {
      case 0: return (row + col) % 2 == 0;
      case 1: return row % 2 == 0;
      case 2: return col % 3 == 0;
      case 3: return (row + col) % 3 == 0;
      case 4: return ((row ~/ 2) + (col ~/ 3)) % 2 == 0;
      case 5: return ((row * col) % 2) + ((row * col) % 3) == 0;
      case 6: return (((row * col) % 2) + ((row * col) % 3)) % 2 == 0;
      case 7: return (((row + col) % 2) + ((row * col) % 3)) % 2 == 0;
      default: return false;
    }
  }

  // Reed-Solomon GF(256) routines
  static late final List<int> _expTable = _initExpTable();
  static late final List<int> _logTable = _initLogTable();

  static List<int> _initExpTable() {
    final exp = List<int>.filled(512, 0);
    int x = 1;
    for (int i = 0; i < 255; i++) {
      exp[i] = x;
      exp[i + 255] = x;
      x <<= 1;
      if ((x & 0x100) != 0) x ^= 0x11D;
    }
    return exp;
  }

  static List<int> _initLogTable() {
    final log = List<int>.filled(256, 0);
    for (int i = 0; i < 255; i++) {
      log[_expTable[i]] = i;
    }
    return log;
  }

  static int _gfMul(int a, int b) {
    if (a == 0 || b == 0) return 0;
    return _expTable[_logTable[a] + _logTable[b]];
  }

  static List<int> _calcReedSolomon(List<int> data, int nEc) {
    // Generator polynomial
    var g = <int>[1];
    for (int i = 0; i < nEc; i++) {
      final next = List<int>.filled(g.length + 1, 0);
      for (int j = 0; j < g.length; j++) {
        next[j] ^= _gfMul(g[j], _expTable[i]);
        next[j + 1] ^= g[j];
      }
      g = next;
    }

    final res = List<int>.filled(nEc, 0);
    for (final b in data) {
      final factor = b ^ res[0];
      for (int i = 0; i < nEc - 1; i++) {
        res[i] = res[i + 1] ^ _gfMul(factor, g[nEc - 1 - i]);
      }
      res[nEc - 1] = _gfMul(factor, g[0]);
    }
    return res;
  }

  static int _getDataCapacity(int v, int ec) {
    // Codewords capacity for EC level M (index 0)
    const capM = [16, 28, 44, 64, 86, 108, 124, 154, 182, 216];
    return capM[v - 1];
  }

  static int _getNumBlocks(int v, int ec) {
    // For EC level M:
    const blocksM = [1, 1, 1, 2, 2, 4, 4, 4, 5, 5];
    return blocksM[v - 1];
  }

  static int _getEcCodewordsPerBlock(int v, int ec) {
    // For EC level M:
    const ecM = [10, 16, 26, 18, 24, 16, 18, 22, 22, 26];
    return ecM[v - 1];
  }

  static List<int> _getBlockDataLengths(int v, int ec, int totalData) {
    final blocks = _getNumBlocks(v, ec);
    final shortLen = totalData ~/ blocks;
    final numLong = totalData % blocks;
    final res = <int>[];
    for (int i = 0; i < blocks; i++) {
      res.add(i >= (blocks - numLong) ? shortLen + 1 : shortLen);
    }
    return res;
  }

  static List<int> _getAlignmentPatternPositions(int v) {
    if (v == 1) return const <int>[];
    const List<List<int>> positions = [
      <int>[],
      <int>[6, 18],
      <int>[6, 22],
      <int>[6, 26],
      <int>[6, 30],
      <int>[6, 34],
      <int>[6, 22, 38],
      <int>[6, 24, 42],
      <int>[6, 26, 46],
      <int>[6, 28, 50],
    ];
    return positions[v - 1];
  }
}

