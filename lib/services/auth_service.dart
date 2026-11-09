// LIBRARY SUPABASE FLUTTER: untuk koneksi ke database cloud Supabase (PostgreSQL)
import 'package:supabase_flutter/supabase_flutter.dart';

// LIBRARY KATEGORI SERVICE: untuk membuat kategori bawaan otomatis saat user baru daftar
import 'kategori_service.dart';

// CLASS UTAMA UNTUK MENANGANI AUTENTIKASI: login, daftar, logout
class AuthService {
  // Inisialisasi client Supabase untuk komunikasi dengan database cloud
  final supabase = Supabase.instance.client;

  // FUNGSI DAFTAR AKUN BENDAHARA (asynchronous karena butuh waktu ke server)
  // async/await: biar aplikasi tidak freeze saat menunggu respons dari Supabase
  Future<String?> signUp({
    required String email,
    required String password,
    required String fullname,
  }) async {
    try {
      // Kirim permintaan daftar ke Supabase Auth (email & password)
      // await: tunggu sampai proses registrasi selesai
      final response = await supabase.auth.signUp(
        email: email,
        password: password,
      );

      // Cek apakah data user berhasil dibuat di database
      if (response.user != null) {
        // Jika "Confirm email" di Supabase aktif, belum ada sesi login (response.session == null)
        // sehingga insert ke tabel profil akan ditolak oleh RLS (Row Level Security)
        if (response.session == null) {
          return 'Akun dibuat. Cek email untuk konfirmasi, lalu login. '
              '(Atau matikan "Confirm email" di Supabase > Authentication > Providers > Email)';
        }
        // Jika email terkonfirmasi, langsung insert data profil ke tabel 'profil'
        // response.user!.id: ID unik otomatis dari Supabase untuk user tersebut
        // fullname: nama lengkap yang diinput user saat registrasi
        await supabase.from('profil').insert({
          'id': response.user!.id,
          'nama_lengkap': fullname,
        });
        // Setelah profil berhasil dibuat, buat kategori bawaan otomatis
        // supaya bendahara baru langsung bisa memakai aplikasi tanpa buat kategori manual
        await KategoriService().seedKategoriDefault();
        // return null berarti tidak ada error, proses daftar berhasil
        return null;
      }
      // Jika response.user null, berarti proses daftar gagal
      return 'gagal daftar';
    } on AuthException catch (e) {
      // Tangkap error spesifik dari Autentikasi Supabase (contoh: email sudah terdaftar)
      return e.message;
    } catch (e) {
      // Tangkap error umum lainnya (contoh: masalah jaringan, server error)
      return 'terjadi kesalahan: $e';
    }
  }

  // FUNGSI LOGIN AKUN BENDAHARA (asynchronous karena butuh waktu ke server)
  // async/await: biar aplikasi tidak freeze saat menunggu verifikasi password dari Supabase
  Future<String?> signIn({
    required String email,
    required String password,
  }) async {
    try {
      // Kirim kredensial email & password ke Supabase untuk autentikasi
      // await: tunggu sampai proses login selesai
      await supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );
      // Jika tidak ada error di atas, berarti login berhasil
      return null;
    } on AuthException catch (e) {
      // Tangkap error spesifik dari Autentikasi (contoh: password salah, email tidak ditemukan)
      return e.message;
    } catch (e) {
      // Tangkap error umum lainnya (contoh: server error, jaringan terputus)
      return 'terjadi kesalahan: $e';
    }
  }

  // FUNGSI LOGOUT: mengakhiri sesi login bendahara
  // void: tidak mengembalikan nilai apapun
  // async: karena butuh kirim request ke server untuk menghapus sesi
  Future<void> signOut() async {
    // Hapus sesi login di Supabase
    await supabase.auth.signOut();
  }

  // GETTER: mengambil data user yang sedang login saat ini
  // User? : tipe data user yang bisa null (jika belum login)
  // supabase.auth.currentUser: property bawaan Supabase untuk mendapatkan user aktif
  User? get currentUser => supabase.auth.currentUser;
}
