import 'package:flutter/material.dart';
import '../../services/anggota_service.dart';
import '../../services/kas_service.dart';
import '../../services/pengaturan_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/format.dart';

// Menampilkan siapa saja yang sudah / belum membayar uang kas, per bulan.
class StatusKasScreen extends StatefulWidget {
  const StatusKasScreen({super.key});

  @override
  State<StatusKasScreen> createState() => _StatusKasScreenState();
}

class _StatusKasScreenState extends State<StatusKasScreen> {
  final _anggotaService = AnggotaService();
  final _kasService = KasService();

  int _tahun = DateTime.now().year;
  List<Anggota> _anggota = [];
  Map<String, Set<BulanKas>> _rekap = {};
  Pengaturan _peng = Pengaturan.kosong;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _muat();
  }

  Future<void> _muat() async {
    setState(() => _loading = true);
    final anggota = await _anggotaService.getAll();
    final rekap = await _kasService.getRekapSemua();
    final peng = await PengaturanService().get(force: true);
    if (!mounted) return;
    setState(() {
      _anggota = anggota;
      _rekap = rekap;
      _peng = peng;
      _loading = false;
    });
  }

  // Bulan ini sudah lewat / sedang berjalan? (bulan mendatang belum dianggap menunggak)
  bool _sudahJatuhTempo(int tahun, int bulan) {
    final now = DateTime.now();
    return urutanBulan((tahun: tahun, bulan: bulan)) <= urutanBulan((tahun: now.year, bulan: now.month));
  }

  // Jumlah bulan menunggak 1 anggota pada tahun yang sedang ditampilkan
  int _hitungBelum(Anggota a) {
    final lunasSet = _rekap[a.id] ?? <BulanKas>{};
    int belum = 0;
    for (int m = 1; m <= 12; m++) {
      final b = (tahun: _tahun, bulan: m);
      if (!lunasSet.contains(b) && _sudahJatuhTempo(_tahun, m) && sudahMulai(a, _peng, b)) belum++;
    }
    return belum;
  }

  @override
  Widget build(BuildContext context) {
    final totalBelum = _anggota.fold<int>(0, (s, a) => s + _hitungBelum(a));
    final anggotaMenunggak = _anggota.where((a) => _hitungBelum(a) > 0).length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Status Uang Kas'),
        backgroundColor: kBlue,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kBlue))
          : Column(
              children: [
                // ---- Pilih tahun ----
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => setState(() => _tahun--)),
                      Text('Tahun $_tahun', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => setState(() => _tahun++)),
                    ],
                  ),
                ),
                // ---- Keterangan warna ----
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Wrap(
                    spacing: 14,
                    children: [
                      _legenda(const Color(0xFFD9F2E3), 'Lunas'),
                      _legenda(const Color(0xFFFBDADA), 'Belum bayar'),
                      _legenda(const Color(0xFFF0F0F0), 'Belum jatuh tempo / belum mulai'),
                    ],
                  ),
                ),
                if (_anggota.isNotEmpty)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.fromLTRB(16, 10, 16, 2),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: totalBelum == 0 ? const Color(0xFFD9F2E3) : const Color(0xFFFBDADA),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      totalBelum == 0
                          ? 'Semua anggota lunas sampai bulan ini'
                          : '$anggotaMenunggak anggota menunggak - total $totalBelum bulan'
                              '${_peng.nominalIuran > 0 ? ' (${rupiah(totalBelum * _peng.nominalIuran)})' : ''}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: totalBelum == 0 ? const Color(0xFF1B6B3A) : const Color(0xFFA3201B),
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                Expanded(
                  child: _anggota.isEmpty
                      ? const Center(child: Text('Belum ada anggota. Tambah dulu di menu Anggota.'))
                      : RefreshIndicator(
                          color: kBlue,
                          onRefresh: _muat,
                          child: ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                            itemCount: _anggota.length,
                            itemBuilder: (ctx, i) => _kartuAnggota(_anggota[i]),
                          ),
                        ),
                ),
              ],
            ),
    );
  }

  Widget _kartuAnggota(Anggota a) {
    final lunasSet = _rekap[a.id] ?? <BulanKas>{};
    int lunas = 0, belum = 0;
    for (int m = 1; m <= 12; m++) {
      if (lunasSet.contains((tahun: _tahun, bulan: m))) {
        lunas++;
      } else if (_sudahJatuhTempo(_tahun, m) && sudahMulai(a, _peng, (tahun: _tahun, bulan: m))) {
        belum++;
      }
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(a.nama, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15))),
                Text('Lunas $lunas', style: const TextStyle(color: Color(0xFF1B6B3A), fontSize: 12)),
                const SizedBox(width: 10),
                Text('Belum $belum',
                    style: TextStyle(color: belum > 0 ? const Color(0xFFA3201B) : kTextGrey, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: List.generate(12, (i) {
                final bulan = i + 1;
                final isLunas = lunasSet.contains((tahun: _tahun, bulan: bulan));
                final jatuhTempo = _sudahJatuhTempo(_tahun, bulan) && sudahMulai(a, _peng, (tahun: _tahun, bulan: bulan));
                final latar = isLunas
                    ? const Color(0xFFD9F2E3)
                    : (jatuhTempo ? const Color(0xFFFBDADA) : const Color(0xFFF0F0F0));
                final warna = isLunas
                    ? const Color(0xFF1B6B3A)
                    : (jatuhTempo ? const Color(0xFFA3201B) : kTextGrey);
                return Container(
                  width: 48,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(color: latar, borderRadius: BorderRadius.circular(8)),
                  alignment: Alignment.center,
                  child: Text(namaBulanSingkat[i], style: TextStyle(fontSize: 12, color: warna, fontWeight: FontWeight.w600)),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }

  Widget _legenda(Color warna, String teks) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 12, height: 12, decoration: BoxDecoration(color: warna, borderRadius: BorderRadius.circular(3))),
          const SizedBox(width: 4),
          Text(teks, style: const TextStyle(fontSize: 11)),
        ],
      );
}
