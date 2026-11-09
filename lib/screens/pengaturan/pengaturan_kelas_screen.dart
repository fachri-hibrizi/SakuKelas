import 'package:flutter/material.dart';
import '../../services/pengaturan_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/format.dart';
import '../transaction/transaction.dart' show RupiahFormatter;

// Pengaturan dasar kelas: dipakai Beranda (saldo), Status Kas (tunggakan) dan PDF.
class PengaturanKelasScreen extends StatefulWidget {
  const PengaturanKelasScreen({super.key});

  @override
  State<PengaturanKelasScreen> createState() => _PengaturanKelasScreenState();
}

class _PengaturanKelasScreenState extends State<PengaturanKelasScreen> {
  final _service = PengaturanService();
  final _namaController = TextEditingController();
  final _iuranController = TextEditingController(text: 'Rp 0');
  final _saldoController = TextEditingController(text: 'Rp 0');
  DateTime? _mulaiKas;
  bool _loading = true;
  bool _menyimpan = false;

  @override
  void initState() {
    super.initState();
    _muat();
  }

  @override
  void dispose() {
    _namaController.dispose();
    _iuranController.dispose();
    _saldoController.dispose();
    super.dispose();
  }

  Future<void> _muat() async {
    final p = await _service.get(force: true);
    if (!mounted) return;
    setState(() {
      _namaController.text = p.namaKelas;
      _iuranController.text = rupiah(p.nominalIuran);
      _saldoController.text = rupiah(p.saldoAwal);
      _mulaiKas = p.mulaiKas;
      _loading = false;
    });
  }

  int _angka(TextEditingController c) => int.tryParse(c.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

  Future<void> _pilihMulai() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _mulaiKas ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: 'Pilih bulan pertama iuran kas',
    );
    if (d != null) setState(() => _mulaiKas = DateTime(d.year, d.month, 1));
  }

  Future<void> _simpan() async {
    setState(() => _menyimpan = true);
    final err = await _service.simpan(Pengaturan(
      namaKelas: _namaController.text,
      nominalIuran: _angka(_iuranController),
      mulaiKas: _mulaiKas,
      saldoAwal: _angka(_saldoController),
    ));
    if (!mounted) return;
    setState(() => _menyimpan = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(err ?? 'Pengaturan disimpan'),
        backgroundColor: err == null ? Colors.green : Colors.red,
      ),
    );
    if (err == null) Navigator.pop(context);
  }

  Widget _bantuan(String teks) => Padding(
        padding: const EdgeInsets.only(top: 6, left: 4, bottom: 18),
        child: Text(teks, style: const TextStyle(fontSize: 12, color: kTextGrey)),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pengaturan Kelas'),
        backgroundColor: kBlue,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kBlue))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextField(
                  controller: _namaController,
                  decoration: const InputDecoration(labelText: 'Nama Kelas', border: OutlineInputBorder()),
                ),
                _bantuan('Tampil di judul laporan PDF.'),
                TextField(
                  controller: _iuranController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [RupiahFormatter()],
                  decoration: const InputDecoration(labelText: 'Iuran kas per bulan', border: OutlineInputBorder()),
                ),
                _bantuan('Nominal terisi otomatis saat mencatat uang kas, dan dipakai menghitung total tunggakan. Isi 0 jika iuran tidak tetap.'),
                InkWell(
                  onTap: _pilihMulai,
                  child: InputDecorator(
                    decoration: const InputDecoration(labelText: 'Kas mulai dikumpulkan', border: OutlineInputBorder()),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(_mulaiKas == null
                              ? 'Belum diatur'
                              : '${namaBulanPanjang[_mulaiKas!.month - 1]} ${_mulaiKas!.year}'),
                        ),
                        const Icon(Icons.calendar_today_outlined, color: kBlue, size: 20),
                      ],
                    ),
                  ),
                ),
                _bantuan('Bulan sebelumnya tidak dihitung sebagai "belum bayar". Jika belum diatur, semua bulan dihitung sejak Januari.'),
                TextField(
                  controller: _saldoController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [RupiahFormatter()],
                  decoration: const InputDecoration(labelText: 'Saldo awal kas', border: OutlineInputBorder()),
                ),
                _bantuan('Uang kas yang sudah ada sebelum memakai aplikasi. Ikut dihitung di saldo Beranda dan laporan.'),
                const SizedBox(height: 4),
                SizedBox(
                  height: 50,
                  child: FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: kBlue),
                    onPressed: _menyimpan ? null : _simpan,
                    child: _menyimpan
                        ? const SizedBox(
                            width: 20, height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Simpan', style: TextStyle(color: Colors.white)),
                  ),
                ),
              ],
            ),
    );
  }
}
