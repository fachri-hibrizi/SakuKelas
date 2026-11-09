import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/format.dart';
import 'pengaturan_service.dart';

// Ringkasan keuangan untuk satu periode (dipakai preview & laporan PDF)
class RingkasanKeuangan {
  final int saldoAwal; // saldo sebelum periode dimulai
  final int masuk; // total pemasukan dalam periode
  final int keluar; // total pengeluaran dalam periode

  const RingkasanKeuangan({required this.saldoAwal, required this.masuk, required this.keluar});

  int get saldoAkhir => saldoAwal + masuk - keluar;
}

class TransactionService {
  final supabase = Supabase.instance.client;

  String? get currentUserId => supabase.auth.currentUser?.id;

  // ====================== TAMBAH ======================
  // Mengembalikan id transaksi yang baru dibuat (null jika gagal)
  Future<({String? id, String? error})> addTransaction({
    required String judul,
    required int nominal,
    required bool isPemasukan,
    String? kategoriId,
    String? anggotaId,
    String? catatan,
    required DateTime tanggal,
  }) async {
    try {
      if (currentUserId == null) return (id: null, error: 'Sesi login berakhir, silakan masuk ulang');

      final inserted = await supabase
          .from('transaksi')
          .insert({
            'pengguna_id': currentUserId,
            'judul': judul,
            'nominal': nominal,
            'jenis': isPemasukan ? 'masuk' : 'keluar',
            'kategori_id': kategoriId,
            'anggota_id': anggotaId,
            'catatan': catatan,
            'tanggal': tanggalDb(tanggal),
          })
          .select('id')
          .single();

      return (id: inserted['id'] as String, error: null);
    } catch (e) {
      debugPrint('addTransaction error: $e');
      return (id: null, error: 'Gagal menyimpan: $e');
    }
  }

  // ====================== UNGGAH BUKTI ======================
  // Unggah 1 foto (bentuk bytes) ke Supabase Storage, lalu catat ke tabel `bukti`.
  // Pakai bytes (bukan dart:io File) supaya jalan di Android/iOS DAN Flutter Web.
  Future<String?> uploadBukti({
    required String transaksiId,
    required Uint8List bytes,
    required String fileName,
  }) async {
    try {
      if (currentUserId == null) return 'Sesi login berakhir, silakan masuk ulang';

      final ext = fileName.contains('.') ? fileName.split('.').last.toLowerCase() : 'jpg';
      final path = '$currentUserId/$transaksiId/${DateTime.now().millisecondsSinceEpoch}.$ext';
      final contentType = ext == 'png' ? 'image/png' : 'image/jpeg';

      await supabase.storage.from('bukti-transaksi').uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(contentType: contentType),
          );
      final publicUrl = supabase.storage.from('bukti-transaksi').getPublicUrl(path);

      await supabase.from('bukti').insert({
        'transaksi_id': transaksiId,
        'url_foto': publicUrl,
      });

      return null;
    } catch (e) {
      debugPrint('uploadBukti error: $e');
      return 'Gagal mengunggah bukti: $e';
    }
  }

  Future<List<String>> getBuktiByTransaksi(String transaksiId) async {
    try {
      final res = await supabase
          .from('bukti')
          .select('url_foto')
          .eq('transaksi_id', transaksiId);
      return (res as List).map((e) => e['url_foto'] as String).toList();
    } catch (e) {
      debugPrint('getBuktiByTransaksi error: $e');
      return [];
    }
  }

  // ====================== BACA ======================
  // kategori, anggota, bukti, dan pembayaran_kas ikut diambil (join otomatis oleh Supabase).
  // [jenis] : 'masuk' / 'keluar' / null (semua)
  Future<List<Map<String, dynamic>>> getTransactions({
    String? jenis,
    String? kategoriId,
    DateTime? dari,
    DateTime? sampai,
  }) async {
    try {
      if (currentUserId == null) return [];

      var query = supabase
          .from('transaksi')
          .select('*, kategori(nama_kategori), anggota(nama), bukti(id, url_foto), pembayaran_kas(bulan, tahun)')
          .eq('pengguna_id', currentUserId!);

      if (jenis != null) query = query.eq('jenis', jenis);
      if (kategoriId != null) query = query.eq('kategori_id', kategoriId);
      if (dari != null) query = query.gte('tanggal', tanggalDb(dari));
      if (sampai != null) query = query.lte('tanggal', tanggalDb(sampai));

      final response = await query
          .order('tanggal', ascending: false)
          .order('dibuat_pada', ascending: false);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('getTransactions error: $e');
      return [];
    }
  }

  // ====================== HAPUS ======================
  // Menghapus transaksi uang kas otomatis "membebaskan" bulan-bulan yang tadinya dibayar.
  Future<String?> deleteTransaction(String id) async {
    try {
      await supabase.from('transaksi').delete().eq('id', id);
      return null;
    } catch (e) {
      return 'Gagal menghapus: $e';
    }
  }

  // ====================== UBAH ======================
  // Memperbarui data utama transaksi. Bulan uang kas & bukti diurus terpisah oleh pemanggil.
  Future<String?> updateTransaction({
    required String id,
    required String judul,
    required int nominal,
    required bool isPemasukan,
    String? kategoriId,
    String? anggotaId,
    String? catatan,
    required DateTime tanggal,
  }) async {
    try {
      if (currentUserId == null) return 'Sesi login berakhir, silakan masuk ulang';
      await supabase
          .from('transaksi')
          .update({
            'judul': judul,
            'nominal': nominal,
            'jenis': isPemasukan ? 'masuk' : 'keluar',
            'kategori_id': kategoriId,
            'anggota_id': anggotaId,
            'catatan': catatan,
            'tanggal': tanggalDb(tanggal),
          })
          .eq('id', id)
          .eq('pengguna_id', currentUserId!);
      return null;
    } catch (e) {
      debugPrint('updateTransaction error: $e');
      return 'Gagal memperbarui: $e';
    }
  }

  // Menghapus 1 foto bukti (baris di tabel `bukti` + file di Storage)
  Future<String?> hapusBukti({required String buktiId, required String url}) async {
    try {
      await supabase.from('bukti').delete().eq('id', buktiId);
    } catch (e) {
      return 'Gagal menghapus bukti: $e';
    }
    try {
      const penanda = '/bukti-transaksi/';
      final i = url.indexOf(penanda);
      if (i != -1) {
        final path = Uri.decodeComponent(url.substring(i + penanda.length).split('?').first);
        await supabase.storage.from('bukti-transaksi').remove([path]);
      }
    } catch (e) {
      debugPrint('hapus file bukti error: $e'); // baris sudah terhapus; file yatim tidak fatal
    }
    return null;
  }

  // ====================== RINGKASAN ======================
  Future<RingkasanKeuangan> getRingkasan({required DateTime dari, required DateTime sampai}) async {
    final data = await getTransactions(sampai: sampai);
    final dariStr = tanggalDb(dari);
    // saldo awal = uang kas sebelum memakai aplikasi (Pengaturan Kelas) + transaksi sebelum periode
    int awal = (await PengaturanService().get()).saldoAwal;
    int masuk = 0, keluar = 0;
    for (final t in data) {
      final nominal = (t['nominal'] as num?)?.toInt() ?? 0;
      final isMasuk = t['jenis'] == 'masuk';
      final tanggal = (t['tanggal'] ?? '').toString();
      if (tanggal.compareTo(dariStr) < 0) {
        awal += isMasuk ? nominal : -nominal; // sebelum periode -> jadi saldo awal
      } else if (isMasuk) {
        masuk += nominal;
      } else {
        keluar += nominal;
      }
    }
    return RingkasanKeuangan(saldoAwal: awal, masuk: masuk, keluar: keluar);
  }

  // Total pengeluaran per kategori dalam periode (uang dipakai untuk apa)
  Future<Map<String, int>> getRekapKategori({DateTime? dari, DateTime? sampai}) async {
    final data = await getTransactions(jenis: 'keluar', dari: dari, sampai: sampai);
    final Map<String, int> rekap = {};
    for (final t in data) {
      final nama = (t['kategori'] as Map?)?['nama_kategori'] as String? ?? 'Tanpa Kategori';
      final nominal = (t['nominal'] as num?)?.toInt() ?? 0;
      rekap[nama] = (rekap[nama] ?? 0) + nominal;
    }
    return rekap;
  }
}
