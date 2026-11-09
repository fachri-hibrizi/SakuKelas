import 'package:flutter/material.dart';
import 'package:moneynotes/screens/login_page/login.dart';
import 'package:moneynotes/services/auth_service.dart';
import 'package:moneynotes/services/transaction_service.dart';
import 'package:moneynotes/services/kas_service.dart';
import 'package:moneynotes/screens/transaction/transaction.dart';
import 'package:moneynotes/screens/transaction/transaction_list_screen.dart';
import 'package:moneynotes/screens/home/home_screen.dart';
import 'package:moneynotes/screens/laporan/export_laporan_screen.dart';
import 'package:moneynotes/screens/kategori/kelola_kategori_screen.dart';
import 'package:moneynotes/screens/anggota/kelola_anggota_screen.dart';
import 'package:moneynotes/screens/kas/status_kas_screen.dart';
import 'package:moneynotes/screens/pengaturan/pengaturan_kelas_screen.dart';

class Navigation extends StatefulWidget {
  const Navigation({super.key});

  @override
  State<Navigation> createState() => _NavigationState();
}

class _NavigationState extends State<Navigation> {
  int _curentIndex = 0;
  int _refresh = 0; // diubah agar Beranda & Riwayat memuat ulang data
  final TransactionService _service = TransactionService();
  final KasService _kasService = KasService();

  // Dipanggil tombol + di tengah: buka form, simpan transaksi,
  // catat bulan uang kas (jika ada), lalu unggah bukti.
  Future<void> _tambahDariNav() async {
    final hasil = await showTambahTransaksiSheet(context);
    if (hasil == null || !mounted) return;

    if (hasil.jumlah <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nominal harus lebih dari 0')),
      );
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: kBlue)),
    );

    // 1) Simpan transaksi
    final hasilSimpan = await _service.addTransaction(
      judul: hasil.judul.isEmpty ? 'Tanpa judul' : hasil.judul,
      nominal: hasil.jumlah,
      isPemasukan: hasil.isPemasukan,
      kategoriId: hasil.kategoriId,
      anggotaId: hasil.anggotaId,
      catatan: hasil.keterangan.isEmpty ? null : hasil.keterangan,
      tanggal: hasil.tanggal,
    );

    if (hasilSimpan.id == null) {
      if (!mounted) return;
      Navigator.pop(context); // tutup loading
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(hasilSimpan.error ?? 'Gagal menyimpan'), backgroundColor: Colors.red),
      );
      return;
    }

    // 2) Catat bulan uang kas yang dibayar (jika kategori uang kas)
    if (hasil.bulanKas.isNotEmpty && hasil.anggotaId != null) {
      final errKas = await _kasService.simpan(
        transaksiId: hasilSimpan.id!,
        anggotaId: hasil.anggotaId!,
        bulan: hasil.bulanKas,
      );
      if (errKas != null) {
        // Batalkan transaksi supaya saldo & status bulan tetap konsisten
        await _service.deleteTransaction(hasilSimpan.id!);
        if (!mounted) return;
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errKas), backgroundColor: Colors.red),
        );
        return;
      }
    }

    // 3) Unggah bukti
    String? errorUnggah;
    for (final pick in hasil.buktiPicks) {
      final err = await _service.uploadBukti(
        transaksiId: hasilSimpan.id!,
        bytes: pick.bytes,
        fileName: pick.fileName,
      );
      if (err != null) errorUnggah = err;
    }

    if (!mounted) return;
    Navigator.pop(context); // tutup loading
    setState(() => _refresh++); // muat ulang Beranda & Riwayat

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(errorUnggah == null
            ? 'Transaksi berhasil disimpan'
            : 'Transaksi tersimpan, tetapi ada bukti yang gagal diunggah: $errorUnggah'),
        backgroundColor: errorUnggah == null ? Colors.green : Colors.orange,
      ),
    );
  }

  Widget get _halaman {
    switch (_curentIndex) {
      case 0:
        return HomeScreen(key: ValueKey('beranda_$_refresh'));
      case 1:
        return TransactionListScreen(key: ValueKey('riwayat_$_refresh'));
      case 2:
        return const ExportLaporanScreen();
      default:
        return const _AkunPage();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Isi halaman dibatasi lebarnya supaya tetap rapi di layar lebar (web/tablet)
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: _halaman,
        ),
      ),

      // Tombol + menempel di tengah, "masuk" ke lekukan bar bawah
      floatingActionButton: FloatingActionButton(
        onPressed: _tambahDariNav,
        backgroundColor: kBlue,
        elevation: 3,
        shape: const CircleBorder(),
        child: const Icon(Icons.add, color: Colors.white, size: 30),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,

      // 2 menu di kiri + ruang kosong untuk tombol + + 2 menu di kanan
      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        notchMargin: 8,
        height: 64,
        padding: EdgeInsets.zero,
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Row(
              children: [
                _itemNav(0, Icons.home_rounded, 'Beranda'),
                _itemNav(1, Icons.receipt_long, 'Riwayat'),
                const SizedBox(width: 72), // ruang untuk tombol +
                _itemNav(2, Icons.picture_as_pdf, 'Laporan'),
                _itemNav(3, Icons.person, 'Akun'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _itemNav(int index, IconData ikon, String label) {
    final aktif = _curentIndex == index;
    final warna = aktif ? kBlue : Colors.grey;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _curentIndex = index),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(ikon, color: warna, size: 24),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: warna,
                fontWeight: aktif ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AkunPage extends StatelessWidget {
  const _AkunPage();

  @override
  Widget build(BuildContext context) {
    final email = AuthService().currentUser?.email ?? '-';
    return Scaffold(
      appBar: AppBar(title: const Text('Akun'), backgroundColor: kBlue, foregroundColor: Colors.white),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Center(
            child: CircleAvatar(
              radius: 36,
              backgroundColor: Color(0xFFE3F2FB),
              child: Icon(Icons.person, color: kBlue, size: 36),
            ),
          ),
          const SizedBox(height: 10),
          Center(child: Text(email, style: const TextStyle(fontWeight: FontWeight.w600))),
          const SizedBox(height: 24),
          ListTile(
            leading: const Icon(Icons.settings, color: kBlue),
            title: const Text('Pengaturan Kelas'),
            subtitle: const Text('Iuran, mulai kas & saldo awal'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PengaturanKelasScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.fact_check, color: kBlue),
            title: const Text('Status Uang Kas'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StatusKasScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.category, color: kBlue),
            title: const Text('Kelola Kategori'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const KelolaKategoriScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.groups, color: kBlue),
            title: const Text('Kelola Anggota'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const KelolaAnggotaScreen())),
          ),
          const Divider(height: 32),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('Keluar', style: TextStyle(color: Colors.red)),
            onTap: () async {
              await AuthService().signOut();
              if (!context.mounted) return;
              Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const Login()));
            },
          ),
        ],
      ),
    );
  }
}
