import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/format.dart';

// MODEL: data 1 anggota kelas
class Anggota {
  final String id;
  final String nama;
  final DateTime? mulaiBayar; // null = ikut "mulai kas" kelas

  const Anggota({required this.id, required this.nama, this.mulaiBayar});

  factory Anggota.fromMap(Map<String, dynamic> map) {
    return Anggota(
      id: map['id'] as String,
      nama: map['nama'] ?? '-',
      mulaiBayar: DateTime.tryParse('${map['mulai_bayar'] ?? ''}'),
    );
  }
}

class AnggotaService {
  final supabase = Supabase.instance.client;
  String? get _uid => supabase.auth.currentUser?.id;

  Future<List<Anggota>> getAll() async {
    if (_uid == null) return [];
    try {
      final res = await supabase
          .from('anggota')
          .select()
          .eq('pengguna_id', _uid!)
          .order('nama');
      return (res as List).map((e) => Anggota.fromMap(e)).toList();
    } catch (e) {
      debugPrint('getAll anggota error: $e');
      return [];
    }
  }

  Future<String?> tambah(String nama, {DateTime? mulaiBayar}) async {
    if (_uid == null) return 'Sesi login berakhir, silakan masuk ulang';
    if (nama.trim().isEmpty) return 'Nama anggota tidak boleh kosong';
    try {
      await supabase.from('anggota').insert({
        'pengguna_id': _uid,
        'nama': nama.trim(),
        if (mulaiBayar != null) 'mulai_bayar': tanggalDb(DateTime(mulaiBayar.year, mulaiBayar.month, 1)),
      });
      return null;
    } catch (e) {
      return 'Gagal menambah anggota: $e';
    }
  }

  Future<String?> ubah(String id, String nama, DateTime? mulaiBayar) async {
    if (nama.trim().isEmpty) return 'Nama anggota tidak boleh kosong';
    try {
      await supabase.from('anggota').update({
        'nama': nama.trim(),
        'mulai_bayar': mulaiBayar == null ? null : tanggalDb(DateTime(mulaiBayar.year, mulaiBayar.month, 1)),
      }).eq('id', id);
      return null;
    } catch (e) {
      return 'Gagal mengubah anggota: $e (sudah menjalankan skema_tambahan.sql?)';
    }
  }

  // Menghapus anggota juga menghapus catatan bulan uang kasnya.
  // Transaksi lamanya tetap ada (hanya nama anggotanya jadi kosong).
  Future<String?> hapus(String id) async {
    try {
      await supabase.from('anggota').delete().eq('id', id);
      return null;
    } catch (e) {
      return 'Gagal menghapus anggota: $e';
    }
  }
}
