import 'package:flutter/material.dart';
import '../../services/pdf_service.dart';
import '../../services/pengaturan_service.dart';
import '../../services/transaction_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/format.dart';

enum _Periode { bulan, semester, tahun, custom }

class ExportLaporanScreen extends StatefulWidget {
  const ExportLaporanScreen({super.key});

  @override
  State<ExportLaporanScreen> createState() => _ExportLaporanScreenState();
}

class _ExportLaporanScreenState extends State<ExportLaporanScreen> {
  final _pdfService = PdfService();
  final _transService = TransactionService();
  final _namaKelasController = TextEditingController(text: 'Kelas Saya');

  _Periode _periode = _Periode.bulan;
  int _geser = 0; // 0 = periode berjalan, -1 = periode sebelumnya, dst.
  DateTime? _customDari;
  DateTime? _customSampai;
  bool _sedangBuat = false;
  late Future<RingkasanKeuangan> _futureRingkasan;

  static const _labelPeriode = {
    _Periode.bulan: '1 Bulan',
    _Periode.semester: '1 Semester',
    _Periode.tahun: '1 Tahun',
    _Periode.custom: 'Atur Sendiri',
  };

  @override
  void initState() {
    super.initState();
    _muatRingkasan();
    // Nama kelas diambil dari Pengaturan Kelas (bisa tetap diubah di sini)
    PengaturanService().get().then((p) {
      if (mounted && _namaKelasController.text == 'Kelas Saya') {
        setState(() => _namaKelasController.text = p.namaKelas);
      }
    });
  }

  @override
  void dispose() {
    _namaKelasController.dispose();
    super.dispose();
  }

  // Menghitung rentang tanggal & label sesuai pilihan periode
  ({DateTime dari, DateTime sampai, String label}) _hitungRentang() {
    final now = DateTime.now();
    switch (_periode) {
      case _Periode.bulan:
        final awal = DateTime(now.year, now.month + _geser, 1);
        return (
          dari: awal,
          sampai: DateTime(awal.year, awal.month + 1, 0),
          label: '${namaBulanPanjang[awal.month - 1]} ${awal.year}',
        );
      case _Periode.semester:
        // Semester Genap = Jan-Jun, Semester Ganjil = Jul-Des
        final indeks = now.year * 2 + (now.month > 6 ? 1 : 0) + _geser;
        final tahun = indeks ~/ 2;
        if (indeks % 2 == 0) {
          return (dari: DateTime(tahun, 1, 1), sampai: DateTime(tahun, 6, 30), label: 'Semester Genap (Jan - Jun $tahun)');
        }
        return (dari: DateTime(tahun, 7, 1), sampai: DateTime(tahun, 12, 31), label: 'Semester Ganjil (Jul - Des $tahun)');
      case _Periode.tahun:
        final tahun = now.year + _geser;
        return (dari: DateTime(tahun, 1, 1), sampai: DateTime(tahun, 12, 31), label: 'Tahun $tahun');
      case _Periode.custom:
        final dari = _customDari ?? DateTime(now.year, now.month, 1);
        final sampai = _customSampai ?? now;
        return (dari: dari, sampai: sampai, label: 'Periode Pilihan Sendiri');
    }
  }

  void _muatRingkasan() {
    final r = _hitungRentang();
    _futureRingkasan = _transService.getRingkasan(dari: r.dari, sampai: r.sampai);
  }

  void _ubahPeriode(_Periode p) {
    setState(() {
      _periode = p;
      _geser = 0;
      _muatRingkasan();
    });
  }

  void _geserPeriode(int arah) {
    setState(() {
      _geser += arah;
      _muatRingkasan();
    });
  }

  Future<void> _pilihTanggalCustom(bool isDari) async {
    final hasil = await showDatePicker(
      context: context,
      initialDate: (isDari ? _customDari : _customSampai) ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (hasil != null) {
      setState(() {
        if (isDari) {
          _customDari = hasil;
        } else {
          _customSampai = hasil;
        }
        _muatRingkasan();
      });
    }
  }

  Future<void> _buatPdf() async {
    final rentang = _hitungRentang();
    if (rentang.sampai.isBefore(rentang.dari)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tanggal akhir tidak boleh lebih awal dari tanggal awal')),
      );
      return;
    }
    setState(() => _sedangBuat = true);
    try {
      final nama = _namaKelasController.text.trim();
      await _pdfService.buatDanBagikan(
        namaKelas: nama.isEmpty ? 'Kelas Saya' : nama,
        labelPeriode: rentang.label,
        dari: rentang.dari,
        sampai: rentang.sampai,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal membuat PDF: $e')));
    } finally {
      if (mounted) setState(() => _sedangBuat = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rentang = _hitungRentang();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ekspor Laporan'),
        backgroundColor: kBlue,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _namaKelasController,
            decoration: const InputDecoration(labelText: 'Nama Kelas', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 20),
          const Text('Pilih Periode', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: _Periode.values.map((p) {
              final aktif = _periode == p;
              return ChoiceChip(
                label: Text(_labelPeriode[p]!),
                selected: aktif,
                selectedColor: kBlue,
                labelStyle: TextStyle(color: aktif ? Colors.white : Colors.black),
                onSelected: (_) => _ubahPeriode(p),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),

          if (_periode == _Periode.custom)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _pilihTanggalCustom(true),
                    child: Text(_customDari == null ? 'Dari tanggal' : tanggalIndo(_customDari!)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _pilihTanggalCustom(false),
                    child: Text(_customSampai == null ? 'Sampai tanggal' : tanggalIndo(_customSampai!)),
                  ),
                ),
              ],
            )
          else
            // Geser ke periode sebelumnya / berikutnya
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF1F4F8),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => _geserPeriode(-1)),
                  Expanded(
                    child: Text(rentang.label,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    onPressed: _geser < 0 ? () => _geserPeriode(1) : null,
                  ),
                ],
              ),
            ),
          const SizedBox(height: 24),

          // ---------- Pratinjau ringkas ----------
          const Text('Pratinjau', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          FutureBuilder<RingkasanKeuangan>(
            future: _futureRingkasan,
            builder: (ctx, snap) {
              final r = snap.data;
              return Card(
                color: const Color(0xFFE3F2FB),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${tanggalIndo(rentang.dari)} s.d. ${tanggalIndo(rentang.sampai)}',
                          style: const TextStyle(color: kTextGrey)),
                      const SizedBox(height: 10),
                      if (r == null)
                        const LinearProgressIndicator(color: kBlue)
                      else ...[
                        _barisRingkas('Saldo awal', r.saldoAwal),
                        _barisRingkas('Pemasukan', r.masuk),
                        _barisRingkas('Pengeluaran', r.keluar),
                        const Divider(),
                        _barisRingkas('Saldo akhir', r.saldoAkhir, tebal: true),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          const Text(
            'PDF berisi: ringkasan saldo, status uang kas tiap anggota per bulan, '
            'rincian tunggakan, penggunaan dana per kategori, dan rincian transaksi.',
            style: TextStyle(fontSize: 12, color: kTextGrey),
          ),
          const SizedBox(height: 20),

          SizedBox(
            height: 50,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: kBlue),
              onPressed: _sedangBuat ? null : _buatPdf,
              icon: _sedangBuat
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.picture_as_pdf, color: Colors.white),
              label: Text(_sedangBuat ? 'Membuat PDF...' : 'Pratinjau, Bagikan & Cetak PDF',
                  style: const TextStyle(color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _barisRingkas(String label, int nilai, {bool tebal = false}) {
    final gaya = TextStyle(fontWeight: tebal ? FontWeight.bold : FontWeight.normal, fontSize: tebal ? 16 : 14);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Text(label, style: gaya), Text(rupiah(nilai), style: gaya)],
      ),
    );
  }
}
