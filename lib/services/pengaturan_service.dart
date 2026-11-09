import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/format.dart';

// Pengaturan kelas milik bendahara (tabel `pengaturan`, satu baris per pengguna).
class Pengaturan {
  final String namaKelas;
  final int nominalIuran; // iuran per bulan (0 = belum diatur)
  final DateTime? mulaiKas; // bulan pertama kas dikumpulkan (null = belum diatur)
  final int saldoAwal; // uang kas sebelum memakai aplikasi

  const Pengaturan({
    required this.namaKelas,
    required this.nominalIuran,
    required this.mulaiKas,
    required this.saldoAwal,
  });

  static const kosong = Pengaturan(namaKelas: 'Kelas Saya', nominalIuran: 0, mulaiKas: null, saldoAwal: 0);

  BulanKas? get mulaiKasBulan => mulaiKas == null ? null : (tahun: mulaiKas!.year, bulan: mulaiKas!.month);

  factory Pengaturan.fromMap(Map<String, dynamic> map) {
    return Pengaturan(
      namaKelas: (map['nama_kelas'] ?? 'Kelas Saya').toString(),
      nominalIuran: (map['nominal_iuran'] as num?)?.toInt() ?? 0,
      mulaiKas: DateTime.tryParse('${map['mulai_kas'] ?? ''}'),
      saldoAwal: (map['saldo_awal'] as num?)?.toInt() ?? 0,
    );
  }
}

class PengaturanService {
  final supabase = Supabase.instance.client;
  String? get _uid => supabase.auth.currentUser?.id;

  // Disimpan sementara supaya Beranda/PDF tidak query berulang-ulang
  static Pengaturan? _cache;
  static String? _cacheUid;

  // Jika tabel belum dibuat / belum ada baris, kembalikan nilai bawaan (aplikasi tetap jalan).
  Future<Pengaturan> get({bool force = false}) async {
    if (_uid == null) return Pengaturan.kosong;
    if (!force && _cache != null && _cacheUid == _uid) return _cache!;
    try {
      final res = await supabase.from('pengaturan').select().eq('pengguna_id', _uid!).maybeSingle();
      final p = res == null ? Pengaturan.kosong : Pengaturan.fromMap(res);
      _cache = p;
      _cacheUid = _uid;
      return p;
    } catch (e) {
      debugPrint('PengaturanService.get error: $e');
      return Pengaturan.kosong;
    }
  }

  Future<String?> simpan(Pengaturan p) async {
    if (_uid == null) return 'Sesi login berakhir, silakan masuk ulang';
    if (p.namaKelas.trim().isEmpty) return 'Nama kelas tidak boleh kosong';
    try {
      await supabase.from('pengaturan').upsert({
        'pengguna_id': _uid,
        'nama_kelas': p.namaKelas.trim(),
        'nominal_iuran': p.nominalIuran,
        'mulai_kas': p.mulaiKas == null ? null : tanggalDb(DateTime(p.mulaiKas!.year, p.mulaiKas!.month, 1)),
        'saldo_awal': p.saldoAwal,
        'diubah_pada': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'pengguna_id');
      _cache = p;
      _cacheUid = _uid;
      return null;
    } catch (e) {
      debugPrint('PengaturanService.simpan error: $e');
      return 'Gagal menyimpan pengaturan: $e (sudah menjalankan skema_tambahan.sql?)';
    }
  }
}
