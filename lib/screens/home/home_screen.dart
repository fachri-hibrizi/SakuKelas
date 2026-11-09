import 'package:flutter/material.dart';
import '../../services/transaction_service.dart';
import '../../services/pengaturan_service.dart';
import '../kategori/kelola_kategori_screen.dart';
import '../anggota/kelola_anggota_screen.dart';
import '../laporan/export_laporan_screen.dart';
import '../kas/status_kas_screen.dart';
import '../transaction/transaction_list_screen.dart';
import '../../theme/app_colors.dart';
import '../../utils/format.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _service = TransactionService();

  late Future<List<Map<String, dynamic>>> _future;

  int _saldoAwal = 0; // dari Pengaturan Kelas

  @override
  void initState() {
    super.initState();
    _future = _service.getTransactions();
    _muatSaldoAwal();
  }

  Future<void> _muatSaldoAwal() async {
    final p = await PengaturanService().get(force: true);
    if (!mounted) return;
    setState(() => _saldoAwal = p.saldoAwal);
  }

  Future<void> _muatUlang() async {
    setState(() => _future = _service.getTransactions());
    _muatSaldoAwal();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          color: kBlue,
          onRefresh: _muatUlang,
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _future,
            builder: (ctx, snap) {
              final data = snap.data ?? [];
              int totalMasuk = 0, totalKeluar = 0;
              for (final t in data) {
                final jumlah = (t['nominal'] as num?)?.toInt() ?? 0;
                if (t['jenis'] == 'masuk') {
                  totalMasuk += jumlah;
                } else {
                  totalKeluar += jumlah;
                }
              }
              final saldo = _saldoAwal + totalMasuk - totalKeluar;
              final terbaru = data.take(5).toList();

              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // ---------- Kartu Saldo ----------
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      color: Color(0xFF0D8BF2),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Saldo Kas Kelas', style: TextStyle(color: Colors.white70, fontSize: 13)),
                        const SizedBox(height: 4),
                        Text(
                          snap.connectionState == ConnectionState.waiting ? '...' : rupiah(saldo),
                          style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(child: _ringkasMini('Masuk', totalMasuk, Icons.arrow_downward)),
                            const SizedBox(width: 12),
                            Expanded(child: _ringkasMini('Keluar', totalKeluar, Icons.arrow_upward)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ---------- Quick Actions ----------
                  const Text('Pengelolaan', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _aksiCepat(context, Icons.fact_check, 'Status Kas',
                            () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StatusKasScreen()))),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _aksiCepat(context, Icons.category, 'Kategori',
                            () => Navigator.push(context, MaterialPageRoute(builder: (_) => const KelolaKategoriScreen()))),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _aksiCepat(context, Icons.groups, 'Anggota',
                            () => Navigator.push(context, MaterialPageRoute(builder: (_) => const KelolaAnggotaScreen()))),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _aksiCepat(context, Icons.picture_as_pdf, 'Ekspor PDF',
                            () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ExportLaporanScreen()))),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // ---------- Transaksi Terbaru ----------
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Transaksi Terbaru', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      TextButton(
                        onPressed: () => Navigator.push(
                            context, MaterialPageRoute(builder: (_) => const TransactionListScreen())),
                        child: const Text('Lihat semua'),
                      ),
                    ],
                  ),
                  if (terbaru.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: Text('Belum ada transaksi', style: TextStyle(color: Colors.grey))),
                    )
                  else
                    ...terbaru.map((t) {
                      final isMasuk = t['jenis'] == 'masuk';
                      final namaKategori = (t['kategori'] as Map?)?['nama_kategori'] as String?;
                      final jumlahBukti = (t['bukti'] as List?)?.length ?? 0;
                      final jumlah = (t['nominal'] as num?)?.toInt() ?? 0;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: isMasuk ? const Color(0xFFE3F8EE) : const Color(0xFFFDE8E8),
                            child: Icon(isMasuk ? Icons.arrow_downward : Icons.arrow_upward,
                                color: isMasuk ? Colors.green : Colors.red),
                          ),
                          title: Text(t['judul'] ?? '-'),
                          subtitle: Text(namaKategori ?? 'Tanpa kategori'),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '${isMasuk ? '+' : '-'}${rupiah(jumlah)}',
                                style: TextStyle(
                                    color: isMasuk ? Colors.green : Colors.red, fontWeight: FontWeight.w600),
                              ),
                              if (jumlahBukti > 0)
                                const Padding(
                                  padding: EdgeInsets.only(top: 2),
                                  child: Icon(Icons.attach_file, size: 14, color: Colors.grey),
                                ),
                            ],
                          ),
                        ),
                      );
                    }),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _ringkasMini(String label, int nilai, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 16),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
                Text(rupiah(nilai),
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _aksiCepat(BuildContext context, IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFE3F2FB),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Icon(icon, color: kBlue),
            const SizedBox(height: 6),
            Text(label, style: const TextStyle(fontSize: 11), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
