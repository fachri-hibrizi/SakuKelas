import 'package:flutter/material.dart';
import '../../services/kategori_service.dart';
import '../../theme/app_colors.dart';

class KelolaKategoriScreen extends StatefulWidget {
  const KelolaKategoriScreen({super.key});

  @override
  State<KelolaKategoriScreen> createState() => _KelolaKategoriScreenState();
}

class _KelolaKategoriScreenState extends State<KelolaKategoriScreen> {
  final _service = KategoriService();
  List<Kategori> _kategori = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _muat();
  }

  Future<void> _muat() async {
    setState(() => _loading = true);
    final data = await _service.getAll();
    if (!mounted) return;
    setState(() {
      _kategori = data;
      _loading = false;
    });
  }

  void _tampilPesan(String pesan) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(pesan)));
  }

  Future<void> _tambahKategori() async {
    final namaController = TextEditingController();
    String jenis = 'keluar';
    bool adalahUangKas = false;

    final simpan = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: const Text('Tambah Kategori'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: namaController,
                decoration: const InputDecoration(hintText: 'Nama kategori baru'),
                autofocus: true,
              ),
              const SizedBox(height: 16),
              const Text('Jenis'),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Pengeluaran'),
                    selected: jenis == 'keluar',
                    onSelected: (_) => setDialog(() {
                      jenis = 'keluar';
                      adalahUangKas = false;
                    }),
                  ),
                  ChoiceChip(
                    label: const Text('Pemasukan'),
                    selected: jenis == 'masuk',
                    onSelected: (_) => setDialog(() => jenis = 'masuk'),
                  ),
                ],
              ),
              if (jenis == 'masuk')
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  activeThumbColor: kBlue,
                  title: const Text('Ini kategori uang kas'),
                  subtitle: const Text('Saat dipilih, bendahara memilih bulan yang dibayar'),
                  value: adalahUangKas,
                  onChanged: (v) => setDialog(() => adalahUangKas = v),
                ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: kBlue),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );

    if (simpan == true) {
      final err = await _service.tambah(nama: namaController.text, jenis: jenis, adalahUangKas: adalahUangKas);
      if (err != null) {
        _tampilPesan(err);
      } else {
        _muat();
      }
    }
  }

  Future<void> _ubahStatus(Kategori k, bool aktifBaru) async {
    final err = await _service.toggleAktif(k.id, aktifBaru);
    if (err != null) {
      _tampilPesan(err);
    } else {
      _muat();
    }
  }

  Widget _kelompok(String judul, List<Kategori> daftar) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(judul, style: const TextStyle(fontWeight: FontWeight.bold, color: kBlueDarkBrand)),
        ),
        if (daftar.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text('Belum ada kategori', style: TextStyle(color: kTextGrey)),
          ),
        ...daftar.map((k) => SwitchListTile(
              activeThumbColor: kBlue,
              title: Row(
                children: [
                  Flexible(child: Text(k.namaKategori)),
                  if (k.adalahUangKas) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE3F2FB),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text('Uang Kas', style: TextStyle(fontSize: 11, color: kBlueDarkBrand)),
                    ),
                  ],
                ],
              ),
              subtitle: Text(k.kategoriAktif
                  ? 'Aktif - muncul di form transaksi'
                  : 'Nonaktif - disembunyikan dari form transaksi'),
              value: k.kategoriAktif,
              onChanged: (v) => _ubahStatus(k, v),
            )),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final masuk = _kategori.where((k) => k.jenis == 'masuk').toList();
    final keluar = _kategori.where((k) => k.jenis == 'keluar').toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kelola Kategori'),
        backgroundColor: kBlue,
        foregroundColor: Colors.white,
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: kBlue,
        onPressed: _tambahKategori,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kBlue))
          : ListView(
              padding: const EdgeInsets.only(bottom: 90),
              children: [
                _kelompok('Kategori Pemasukan', masuk),
                _kelompok('Kategori Pengeluaran', keluar),
              ],
            ),
    );
  }
}
