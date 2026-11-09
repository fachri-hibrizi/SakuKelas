import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/format.dart';
import 'anggota_service.dart';
import 'pengaturan_service.dart';

// Bulan pertama anggota ini WAJIB membayar:
// yang paling akhir antara "mulai bayar" anggota dan "mulai kas" kelas (null = tanpa batas).
BulanKas? bulanMulaiWajib(Anggota a, Pengaturan p) {
  final m1 = a.mulaiBayar == null ? null : (tahun: a.mulaiBayar!.year, bulan: a.mulaiBayar!.month);
  final m2 = p.mulaiKasBulan;
  if (m1 == null) return m2;
  if (m2 == null) return m1;
  return urutanBulan(m1) >= urutanBulan(m2) ? m1 : m2;
}

// false = bulan [b] sebelum anggota mulai iuran (tidak boleh dihitung menunggak)
bool sudahMulai(Anggota a, Pengaturan p, BulanKas b) {
  final m = bulanMulaiWajib(a, p);
  return m == null || urutanBulan(b) >= urutanBulan(m);
}

// Mengelola data pembayaran uang kas per bulan (tabel `pembayaran_kas`).
class KasService {
  final supabase = Supabase.instance.client;
  String? get _uid => supabase.auth.currentUser?.id;

  // Bulan-bulan yang SUDAH dibayar oleh satu anggota
  // [kecualiTransaksiId] dipakai saat EDIT: bulan milik transaksi itu sendiri tidak dianggap lunas
  Future<Set<BulanKas>> getBulanLunas(String anggotaId, {String? kecualiTransaksiId}) async {
    try {
      var query = supabase
          .from('pembayaran_kas')
          .select('tahun, bulan')
          .eq('anggota_id', anggotaId);
      if (kecualiTransaksiId != null) query = query.neq('transaksi_id', kecualiTransaksiId);
      final res = await query;
      return (res as List)
          .map<BulanKas>((e) => (tahun: (e['tahun'] as num).toInt(), bulan: (e['bulan'] as num).toInt()))
          .toSet();
    } catch (e) {
      debugPrint('getBulanLunas error: $e');
      return {};
    }
  }

  // Pembayaran semua anggota: { id_anggota : {bulan-bulan yang sudah dibayar} }
  Future<Map<String, Set<BulanKas>>> getRekapSemua() async {
    final hasil = <String, Set<BulanKas>>{};
    if (_uid == null) return hasil;
    try {
      final res = await supabase
          .from('pembayaran_kas')
          .select('anggota_id, tahun, bulan')
          .eq('pengguna_id', _uid!);
      for (final e in (res as List)) {
        final id = e['anggota_id'] as String;
        hasil.putIfAbsent(id, () => <BulanKas>{});
        hasil[id]!.add((tahun: (e['tahun'] as num).toInt(), bulan: (e['bulan'] as num).toInt()));
      }
    } catch (e) {
      debugPrint('getRekapSemua error: $e');
    }
    return hasil;
  }

  // Hapus semua catatan bulan milik satu transaksi (dipakai saat edit transaksi uang kas)
  Future<String?> hapusByTransaksi(String transaksiId) async {
    try {
      await supabase.from('pembayaran_kas').delete().eq('transaksi_id', transaksiId);
      return null;
    } catch (e) {
      return 'Gagal memperbarui bulan uang kas: $e';
    }
  }

  // Simpan bulan-bulan yang dibayar untuk satu transaksi uang kas
  Future<String?> simpan({
    required String transaksiId,
    required String anggotaId,
    required List<BulanKas> bulan,
  }) async {
    if (_uid == null) return 'Sesi login berakhir, silakan masuk ulang';
    try {
      await supabase.from('pembayaran_kas').insert(
            bulan
                .map((b) => {
                      'pengguna_id': _uid,
                      'transaksi_id': transaksiId,
                      'anggota_id': anggotaId,
                      'bulan': b.bulan,
                      'tahun': b.tahun,
                    })
                .toList(),
          );
      return null;
    } on PostgrestException catch (e) {
      if (e.code == '23505') return 'Sebagian bulan yang dipilih ternyata sudah lunas sebelumnya';
      return 'Gagal menyimpan bulan uang kas: ${e.message}';
    } catch (e) {
      return 'Gagal menyimpan bulan uang kas: $e';
    }
  }
}
