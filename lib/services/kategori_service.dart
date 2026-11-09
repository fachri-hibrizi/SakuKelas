import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// MODEL: data 1 kategori
class Kategori {
  final String id;
  final String namaKategori;
  final String jenis; // 'masuk' atau 'keluar'
  final bool kategoriAktif;
  final bool adalahUangKas; // true = kategori iuran bulanan (ada pilihan bulan)

  const Kategori({
    required this.id,
    required this.namaKategori,
    required this.jenis,
    required this.kategoriAktif,
    required this.adalahUangKas,
  });

  factory Kategori.fromMap(Map<String, dynamic> map) {
    return Kategori(
      id: map['id'] as String,
      namaKategori: map['nama_kategori'] ?? '-',
      jenis: map['jenis'] ?? 'keluar',
      kategoriAktif: map['kategori_aktif'] ?? true,
      adalahUangKas: map['adalah_uang_kas'] ?? false,
    );
  }
}

class KategoriService {
  final supabase = Supabase.instance.client;
  String? get _uid => supabase.auth.currentUser?.id;

  // Supaya pengecekan "sudah ada kategori atau belum" tidak diulang terus
  static String? _penggunaSudahDicek;

  // Kategori bawaan sesuai blueprint SakuKelas
  Future<void> seedKategoriDefault() async {
    if (_uid == null) return;
    try {
      await supabase.from('kategori').insert([
        {'pengguna_id': _uid, 'nama_kategori': 'Uang Kas', 'jenis': 'masuk', 'adalah_uang_kas': true},
        {'pengguna_id': _uid, 'nama_kategori': 'Donasi', 'jenis': 'masuk', 'adalah_uang_kas': false},
        {'pengguna_id': _uid, 'nama_kategori': 'Kebutuhan Kelas', 'jenis': 'keluar', 'adalah_uang_kas': false},
        {'pengguna_id': _uid, 'nama_kategori': 'Event', 'jenis': 'keluar', 'adalah_uang_kas': false},
        {'pengguna_id': _uid, 'nama_kategori': 'Kesenangan', 'jenis': 'keluar', 'adalah_uang_kas': false},
      ]);
    } catch (e) {
      debugPrint('seedKategoriDefault error: $e');
    }
  }

  // Jika pengguna belum punya kategori sama sekali (akun baru / akun lama),
  // buat kategori bawaan secara otomatis.
  Future<void> _pastikanAdaKategori() async {
    if (_uid == null || _penggunaSudahDicek == _uid) return;
    try {
      final ada = await supabase.from('kategori').select('id').eq('pengguna_id', _uid!).limit(1);
      if ((ada as List).isEmpty) await seedKategoriDefault();
      _penggunaSudahDicek = _uid;
    } catch (e) {
      debugPrint('_pastikanAdaKategori error: $e');
    }
  }

  // Semua kategori (untuk layar Kelola Kategori)
  Future<List<Kategori>> getAll() async {
    if (_uid == null) return [];
    await _pastikanAdaKategori();
    try {
      final res = await supabase
          .from('kategori')
          .select()
          .eq('pengguna_id', _uid!)
          .order('jenis', ascending: true)
          .order('dibuat_pada', ascending: true);
      return (res as List).map((e) => Kategori.fromMap(e)).toList();
    } catch (e) {
      debugPrint('getAll kategori error: $e');
      return [];
    }
  }

  // Hanya kategori yang aktif (untuk dropdown di form transaksi)
  Future<List<Kategori>> getAktif() async {
    final semua = await getAll();
    return semua.where((k) => k.kategoriAktif).toList();
  }

  Future<String?> tambah({
    required String nama,
    required String jenis,
    bool adalahUangKas = false,
  }) async {
    if (_uid == null) return 'Sesi login berakhir, silakan masuk ulang';
    if (nama.trim().isEmpty) return 'Nama kategori tidak boleh kosong';
    try {
      await supabase.from('kategori').insert({
        'pengguna_id': _uid,
        'nama_kategori': nama.trim(),
        'jenis': jenis,
        'adalah_uang_kas': jenis == 'masuk' && adalahUangKas,
      });
      return null;
    } on PostgrestException catch (e) {
      if (e.code == '23505') return 'Kategori "${nama.trim()}" sudah ada';
      return 'Gagal menambah kategori: ${e.message}';
    } catch (e) {
      return 'Gagal menambah kategori: $e';
    }
  }

  // Aktif/nonaktifkan (bukan dihapus, supaya riwayat transaksi lama tetap aman)
  Future<String?> toggleAktif(String id, bool aktifBaru) async {
    try {
      await supabase.from('kategori').update({'kategori_aktif': aktifBaru}).eq('id', id);
      return null;
    } catch (e) {
      return 'Gagal mengubah status: $e';
    }
  }
}
