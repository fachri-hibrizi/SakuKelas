import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../utils/format.dart';
import 'transaction_service.dart';
import 'anggota_service.dart';
import 'kas_service.dart';
import 'pengaturan_service.dart';

// Membuat laporan kas dalam bentuk PDF lalu membuka dialog bagikan/cetak.
// Catatan: teks PDF sengaja hanya memakai karakter ASCII biasa
// (font bawaan PDF tidak mendukung simbol seperti centang atau tanda pisah panjang).
class PdfService {
  final _transaksi = TransactionService();
  final _anggota = AnggotaService();
  final _kas = KasService();

  static const _hijauMuda = PdfColor.fromInt(0xFFD9F2E3);
  static const _hijauTua = PdfColor.fromInt(0xFF1B6B3A);
  static const _merahMuda = PdfColor.fromInt(0xFFFBDADA);
  static const _merahTua = PdfColor.fromInt(0xFFA3201B);
  static const _biruMuda = PdfColor.fromInt(0xFFD6E9FA);
  static const _abuMuda = PdfColor.fromInt(0xFFF0F0F0);

  Future<void> buatDanBagikan({
    required String namaKelas,
    required String labelPeriode,
    required DateTime dari,
    required DateTime sampai,
  }) async {
    final ringkasan = await _transaksi.getRingkasan(dari: dari, sampai: sampai);
    final daftarTransaksi = await _transaksi.getTransactions(dari: dari, sampai: sampai);
    final rekapKategori = await _transaksi.getRekapKategori(dari: dari, sampai: sampai);
    final daftarAnggota = await _anggota.getAll();
    final rekapKas = await _kas.getRekapSemua();
    final bulanPeriode = daftarBulan(dari, sampai);
    final peng = await PengaturanService().get(force: true);
    final adaIuran = peng.nominalIuran > 0;
    final anggotaById = {for (final a in daftarAnggota) a.id: a};

    // Status satu anggota pada satu bulan: 'Lunas' / 'Belum' / '-' (belum jatuh tempo)
    final sekarang = DateTime.now();
    final urutanSekarang = urutanBulan((tahun: sekarang.year, bulan: sekarang.month));
    String statusKas(String idAnggota, BulanKas b) {
      if (rekapKas[idAnggota]?.contains(b) ?? false) return 'Lunas';
      final a = anggotaById[idAnggota];
      if (a != null && !sudahMulai(a, peng, b)) return '-'; // sebelum anggota mulai iuran
      return urutanBulan(b) > urutanSekarang ? '-' : 'Belum';
    }

    // Tunggakan: bulan-bulan yang sudah lewat tapi belum dibayar
    final tunggakan = <Anggota, List<BulanKas>>{};
    for (final a in daftarAnggota) {
      final belum = bulanPeriode.where((b) => statusKas(a.id, b) == 'Belum').toList();
      if (belum.isNotEmpty) tunggakan[a] = belum;
    }

    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(28),
        header: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('Laporan Kas Kelas - $namaKelas',
                style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
            pw.Text('Periode: $labelPeriode (${tanggalIndo(dari)} s.d. ${tanggalIndo(sampai)})',
                style: const pw.TextStyle(fontSize: 10)),
            pw.Text('Dicetak pada: ${tanggalIndo(DateTime.now())}', style: const pw.TextStyle(fontSize: 8)),
            pw.Divider(),
          ],
        ),
        footer: (ctx) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text('Halaman ${ctx.pageNumber} dari ${ctx.pagesCount}',
              style: const pw.TextStyle(fontSize: 8)),
        ),
        build: (ctx) => [
          // ---------- 1. Ringkasan Keuangan ----------
          _judul('1. Ringkasan Keuangan'),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey400),
            columnWidths: {0: const pw.FlexColumnWidth(3), 1: const pw.FlexColumnWidth(2)},
            children: [
              _baris2('Saldo awal periode', rupiah(ringkasan.saldoAwal)),
              _baris2('Total pemasukan', rupiah(ringkasan.masuk)),
              _baris2('Total pengeluaran', rupiah(ringkasan.keluar)),
              _baris2('Saldo akhir periode', rupiah(ringkasan.saldoAkhir), tebal: true, latar: _biruMuda),
            ],
          ),
          pw.SizedBox(height: 16),

          // ---------- 2. Status Uang Kas per Bulan ----------
          _judul('2. Status Uang Kas per Bulan (${daftarAnggota.length} anggota)'),
          if (daftarAnggota.isEmpty)
            pw.Text('Belum ada data anggota.', style: const pw.TextStyle(fontSize: 9))
          else
            ..._tabelStatusKas(daftarAnggota, bulanPeriode, statusKas),
          pw.SizedBox(height: 6),
          pw.Text('Keterangan: Lunas = sudah bayar, Belum = sudah lewat tetapi belum bayar, - = belum jatuh tempo.',
              style: const pw.TextStyle(fontSize: 8)),
          pw.SizedBox(height: 12),

          // ---------- 3. Rincian Tunggakan ----------
          _judul('3. Rincian Tunggakan Uang Kas'),
          if (tunggakan.isEmpty)
            pw.Text('Semua anggota sudah lunas untuk periode ini.', style: const pw.TextStyle(fontSize: 9))
          else
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey400),
              columnWidths: {
                0: const pw.FlexColumnWidth(2),
                1: const pw.FlexColumnWidth(1),
                2: const pw.FlexColumnWidth(7),
                if (adaIuran) 3: const pw.FlexColumnWidth(2),
              },
              children: [
                _barisJudul(['Nama Anggota', 'Jumlah Bulan', 'Bulan yang Belum Dibayar', if (adaIuran) 'Total Tunggakan']),
                ...tunggakan.entries.map((e) => pw.TableRow(children: [
                      _sel(e.key.nama),
                      _sel('${e.value.length} bulan'),
                      _sel(e.value.map(labelBulan).join(', ')),
                      if (adaIuran) _sel(rupiah(e.value.length * peng.nominalIuran)),
                    ])),
              ],
            ),
          if (tunggakan.isNotEmpty && adaIuran)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 4),
              child: pw.Text(
                'Total tunggakan seluruh anggota: ${rupiah(tunggakan.values.fold<int>(0, (s, l) => s + l.length) * peng.nominalIuran)} '
                '(iuran ${rupiah(peng.nominalIuran)} per bulan)',
                style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
              ),
            ),
          pw.SizedBox(height: 16),

          // ---------- 4. Penggunaan Dana ----------
          _judul('4. Penggunaan Dana (Pengeluaran per Kategori)'),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey400),
            columnWidths: {0: const pw.FlexColumnWidth(3), 1: const pw.FlexColumnWidth(2)},
            children: [
              _barisJudul(['Kategori', 'Total']),
              ...rekapKategori.entries.map((e) => _baris2(e.key, rupiah(e.value))),
              if (rekapKategori.isEmpty) _baris2('Tidak ada pengeluaran pada periode ini', '-'),
            ],
          ),
          pw.SizedBox(height: 16),

          // ---------- 5. Rincian Transaksi ----------
          _judul('5. Rincian Transaksi'),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey400),
            columnWidths: {
              0: const pw.FlexColumnWidth(1.4),
              1: const pw.FlexColumnWidth(3.6),
              2: const pw.FlexColumnWidth(1),
              3: const pw.FlexColumnWidth(1.8),
              4: const pw.FlexColumnWidth(1.8),
              5: const pw.FlexColumnWidth(1.8),
              6: const pw.FlexColumnWidth(0.9),
            },
            children: [
              _barisJudul(['Tanggal', 'Keterangan', 'Jenis', 'Kategori', 'Anggota', 'Nominal', 'Bukti']),
              ...daftarTransaksi.map((t) {
                final tanggal = DateTime.tryParse('${t['tanggal']}') ?? DateTime.now();
                final isMasuk = t['jenis'] == 'masuk';
                final kategori = (t['kategori'] as Map?)?['nama_kategori'] ?? '-';
                final anggota = (t['anggota'] as Map?)?['nama'] ?? '-';
                final jumlahBukti = (t['bukti'] as List?)?.length ?? 0;
                final nominal = (t['nominal'] as num?)?.toInt() ?? 0;

                // Untuk uang kas, tampilkan bulan yang dibayar
                final bulanDibayar = ((t['pembayaran_kas'] as List?) ?? [])
                    .map<BulanKas>((e) => (tahun: (e['tahun'] as num).toInt(), bulan: (e['bulan'] as num).toInt()))
                    .toList()
                  ..sort((a, b) => urutanBulan(a).compareTo(urutanBulan(b)));
                final keterangan = bulanDibayar.isEmpty
                    ? '${t['judul'] ?? '-'}'
                    : '${t['judul'] ?? '-'} (${bulanDibayar.map(labelBulan).join(', ')})';

                return pw.TableRow(children: [
                  _sel(tanggalIndo(tanggal), ukuran: 8),
                  _sel(keterangan, ukuran: 8),
                  _sel(isMasuk ? 'Masuk' : 'Keluar', ukuran: 8),
                  _sel('$kategori', ukuran: 8),
                  _sel('$anggota', ukuran: 8),
                  _sel('${isMasuk ? '+' : '-'}${rupiah(nominal)}', ukuran: 8),
                  _sel(jumlahBukti > 0 ? 'Ada ($jumlahBukti)' : '-', ukuran: 8),
                ]);
              }),
              if (daftarTransaksi.isEmpty)
                pw.TableRow(children: [
                  _sel('-'), _sel('Tidak ada transaksi pada periode ini'), _sel('-'), _sel('-'), _sel('-'), _sel('-'), _sel('-'),
                ]),
            ],
          ),
        ],
      ),
    );

    final nama = 'laporan-kas-${dari.year}${dari.month.toString().padLeft(2, '0')}'
        '-${sampai.year}${sampai.month.toString().padLeft(2, '0')}.pdf';
    final bytes = await doc.save();
    // layoutPdf = halaman pratinjau bawaan dengan tombol Cetak & Bagikan (sesuai blueprint)
    await Printing.layoutPdf(onLayout: (_) async => bytes, name: nama);
  }

  // Tabel matriks: baris = anggota, kolom = bulan. Dipecah per 12 bulan agar muat di kertas.
  List<pw.Widget> _tabelStatusKas(
    List<Anggota> anggota,
    List<BulanKas> bulan,
    String Function(String, BulanKas) statusKas,
  ) {
    final hasil = <pw.Widget>[];
    for (int mulai = 0; mulai < bulan.length; mulai += 12) {
      final potongan = bulan.sublist(mulai, mulai + 12 > bulan.length ? bulan.length : mulai + 12);
      // Tabel langsung (tanpa dibungkus Padding) supaya bisa terpotong ke halaman berikutnya
      // bila jumlah anggota banyak.
      hasil.add(
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey400),
          columnWidths: {
            0: const pw.FixedColumnWidth(130),
            for (int i = 1; i <= potongan.length; i++) i: const pw.FixedColumnWidth(44),
          },
          children: [
            _barisJudul([
              'Nama Anggota',
              ...potongan.map((b) => '${namaBulanSingkat[b.bulan - 1]} ${b.tahun % 100}'),
            ], ukuran: 8),
            ...anggota.map((a) => pw.TableRow(children: [
                  _sel(a.nama, ukuran: 8),
                  ...potongan.map((b) {
                    final status = statusKas(a.id, b);
                    return _sel(
                      status,
                      ukuran: 7,
                      tengah: true,
                      latar: status == 'Lunas' ? _hijauMuda : (status == 'Belum' ? _merahMuda : _abuMuda),
                      warna: status == 'Lunas' ? _hijauTua : (status == 'Belum' ? _merahTua : PdfColors.grey700),
                    );
                  }),
                ])),
          ],
        ),
      );
      hasil.add(pw.SizedBox(height: 8));
    }
    return hasil;
  }

  pw.Widget _judul(String teks) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 6),
        child: pw.Text(teks, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
      );

  pw.Widget _sel(
    String teks, {
    double ukuran = 9,
    bool tebal = false,
    bool tengah = false,
    PdfColor? latar,
    PdfColor? warna,
  }) =>
      pw.Container(
        color: latar,
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        alignment: tengah ? pw.Alignment.center : pw.Alignment.centerLeft,
        child: pw.Text(
          teks,
          style: pw.TextStyle(
            fontSize: ukuran,
            color: warna,
            fontWeight: tebal ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
        ),
      );

  pw.TableRow _barisJudul(List<String> kolom, {double ukuran = 9}) => pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.blue100),
        children: [
          for (int i = 0; i < kolom.length; i++)
            _sel(kolom[i], ukuran: ukuran, tebal: true, tengah: i > 0 && kolom.length > 3 && ukuran < 9),
        ],
      );

  pw.TableRow _baris2(String a, String b, {bool tebal = false, PdfColor? latar}) => pw.TableRow(
        children: [_sel(a, tebal: tebal, latar: latar), _sel(b, tebal: tebal, latar: latar)],
      );
}
