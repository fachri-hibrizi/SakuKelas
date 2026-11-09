import 'package:flutter/material.dart';
import 'package:moneynotes/services/transaction_service.dart';
import 'package:moneynotes/services/kas_service.dart';
import 'package:moneynotes/services/kategori_service.dart';

// File pop-up Tambah Transaksi dari langkah sebelumnya.
// Mengandung konstanta kBlue, kTextDark, dll. serta showTambahTransaksiSheet().
import 'transaction.dart';
import 'bukti_viewer_screen.dart';
import '../../utils/format.dart';

// ---- Warna tambahan khusus halaman ini ----
// (kBlue, kBlueLight, dll. ikut terbawa dari transaction.dart yang meng-export app_colors.dart)
const Color kRed = Color(0xFFD92D20);
const Color kCatBlue = Color(0xFF1E5BC6); // biru untuk kategori Event
const Color kOrange = Color(0xFFF28C1B); // oranye untuk kategori Kesenangan
const Color kBlueSoft = Color(0xFFE3F2FB); // biru muda lembut (warna tema)
const Color kRedSoft = Color(0xFFFDE8E8);
const Color kCatBlueSoft = Color(0xFFE3EEFB);
const Color kOrangeSoft = Color(0xFFFFF1DC);
const Color kSubtitle = Color(0xFF5F6368);
const Color kBlueDark = Color(0xFF024D7C); // teks chip yang dipilih

// MODEL: data 1 transaksi untuk ditampilkan di UI
class Transaksi {
  final String? id; // id dari Supabase (dipakai saat hapus)
  final String judul; // judul transaksi
  final bool isPemasukan; // true = pemasukan, false = pengeluaran
  final String kategori; // nama kategori hasil join tabel kategori
  final String? anggotaNama; // nama anggota (khusus pemasukan), bisa null
  final DateTime waktu; // tanggal transaksi
  final int jumlah; // nominal uang
  final int jumlahBukti; // jumlah foto bukti yang dilampirkan
  final String? ringkasBulanKas; // contoh: "Jan 2026, Feb 2026" (khusus uang kas)
  // ---- data mentah, dipakai saat EDIT ----
  final String? kategoriId;
  final String? anggotaId;
  final String catatan;
  final List<BulanKas> bulanKasList;
  final List<BuktiLama> buktiLama;

  // Constructor
  const Transaksi({
    this.id,
    required this.judul,
    required this.isPemasukan,
    required this.kategori,
    this.anggotaNama,
    required this.waktu,
    required this.jumlah,
    this.jumlahBukti = 0,
    this.ringkasBulanKas,
    this.kategoriId,
    this.anggotaId,
    this.catatan = '',
    this.bulanKasList = const [],
    this.buktiLama = const [],
  });

  // Mengubah data Map dari Supabase (hasil join) menjadi objek Transaksi
  factory Transaksi.fromMap(Map<String, dynamic> map) {
    // kategori & anggota datang sebagai nested object hasil embed Supabase,
    // contoh: {'nama_kategori': 'Event'} atau null kalau tidak ada relasi.
    final kategoriMap = map['kategori'] as Map<String, dynamic>?;
    final anggotaMap = map['anggota'] as Map<String, dynamic>?;
    final buktiList = map['bukti'] as List?;
    final kasList = (map['pembayaran_kas'] as List?) ?? [];

    // Susun bulan uang kas yang dibayar, urut dari yang paling awal
    final bulanKas = kasList
        .map<BulanKas>((e) => (tahun: (e['tahun'] as num).toInt(), bulan: (e['bulan'] as num).toInt()))
        .toList()
      ..sort((a, b) => urutanBulan(a).compareTo(urutanBulan(b)));

    return Transaksi(
      id: map['id'] as String?,
      judul: map['judul'] ?? '-',
      isPemasukan: map['jenis'] == 'masuk',
      kategori: kategoriMap?['nama_kategori'] as String? ?? 'Tanpa Kategori',
      anggotaNama: anggotaMap?['nama'] as String?,
      waktu: DateTime.tryParse(map['tanggal']?.toString() ?? '') ?? DateTime.now(),
      jumlah: (map['nominal'] as num?)?.toInt() ?? 0,
      jumlahBukti: buktiList?.length ?? 0,
      ringkasBulanKas: bulanKas.isEmpty ? null : bulanKas.map(labelBulan).join(', '),
      kategoriId: map['kategori_id'] as String?,
      anggotaId: map['anggota_id'] as String?,
      catatan: (map['catatan'] ?? '').toString(),
      bulanKasList: bulanKas,
      buktiLama: (buktiList ?? [])
          .map((e) => BuktiLama(id: e['id'].toString(), url: (e['url_foto'] ?? '').toString()))
          .toList(),
    );
  }
}

// Enum untuk pilihan filter
enum FilterTransaksi {
  semua, // tampilkan semua
  pemasukan, // hanya jenis 'masuk'
  pengeluaran, // hanya jenis 'keluar'
}

// ---------- Halaman ----------

class TransactionListScreen extends StatefulWidget {
  const TransactionListScreen({super.key});

  @override
  State<TransactionListScreen> createState() => _TransactionListScreenState();
}

class _TransactionListScreenState extends State<TransactionListScreen> {
  FilterTransaksi _filter = FilterTransaksi.semua;
  List<Transaksi> _data = [];
  bool _isLoading = true;

  final TransactionService _service = TransactionService();
  final KasService _kasService = KasService();
  final KategoriService _kategoriService = KategoriService();

  // ---- filter lanjutan (blueprint: filter kategori & rentang tanggal) ----
  String? _kategoriFilterId;
  String? _kategoriFilterNama;
  DateTimeRange? _rentang;
  List<Kategori> _semuaKategori = [];

  bool get _adaFilterLanjut => _kategoriFilterId != null || _rentang != null;

  static const _bulan = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'Mei',
    'Jun',
    'Jul',
    'Agu',
    'Sep',
    'Okt',
    'Nov',
    'Des',
  ];

  // ----------------------------------------------------------
  // initState: dipanggil 1 kali saat halaman pertama kali dibuka
  // ----------------------------------------------------------
  @override
  void initState() {
    super.initState();
    // Langsung ambil data dari Supabase
    _loadData();
    _muatKategori();
  }

  Future<void> _muatKategori() async {
    final k = await _kategoriService.getAll();
    if (!mounted) return;
    setState(() => _semuaKategori = k);
  }

  // ----------------------------------------------------------
  // _loadData: mengambil data dari Supabase sesuai filter
  // ----------------------------------------------------------
  Future<void> _loadData() async {
    // Tampilkan loading di layar
    setState(() {
      _isLoading = true;
    });

    // Tentukan filter untuk dikirim ke Supabase
    String? jenis;
    if (_filter == FilterTransaksi.pemasukan) {
      jenis = 'masuk'; // hanya pemasukan
    }
    if (_filter == FilterTransaksi.pengeluaran) {
      jenis = 'keluar'; // hanya pengeluaran
    }
    // jika _filter == semua, jenis tetap null (ambil semua)

    // Panggil service untuk mengambil data
    final result = await _service.getTransactions(
      jenis: jenis,
      kategoriId: _kategoriFilterId,
      dari: _rentang?.start,
      sampai: _rentang?.end,
    );

    // Cek apakah widget masih ada di layar
    if (!mounted) return;

    // Ubah setiap Map menjadi objek Transaksi, lalu update UI
    setState(() {
      _data = result.map((e) => Transaksi.fromMap(e)).toList();
      _isLoading = false; // matikan loading
    });
  }

  // ----------------------------------------------------------
  // _tampil: list yang sudah diurutkan (terbaru di atas)
  // ----------------------------------------------------------
  List<Transaksi> get _tampil {
    // Salin list, lalu urutkan dari tanggal terbaru ke terlama
    final list = [..._data];
    list.sort((a, b) => b.waktu.compareTo(a.waktu));
    return list;
  }

  // ----------------------------------------------------------
  // _rupiah: mengubah angka 1250000 menjadi "Rp 1.250.000"
  // ----------------------------------------------------------
  String _rupiah(int n) {
    final s = n.toString(); // ubah int jadi String
    final buf = StringBuffer();

    // Sisipkan titik setiap 3 digit dari belakang
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) {
        buf.write('.');
      }
      buf.write(s[i]);
    }

    return 'Rp $buf';
  }

  // ----------------------------------------------------------
  // _waktuText: mengubah DateTime menjadi "25 Mei 2024 • 10:30"
  // ----------------------------------------------------------
  String _waktuText(DateTime d) {
    final jam = d.hour.toString().padLeft(2, '0'); // 9 -> "09"
    final menit = d.minute.toString().padLeft(2, '0'); // 5 -> "05"
    return '${d.day} ${_bulan[d.month - 1]} ${d.year} • $jam:$menit';
  }

  // Catatan: tambah transaksi dilakukan lewat tombol + di nav.dart
  // (biar bukti & kategori ikut tersimpan dari satu tempat saja).
  // Di sini kita hanya menampilkan & mengelola daftar yang sudah ada.

  // ----------------------------------------------------------
  // Filter lanjutan: kategori & rentang tanggal
  // ----------------------------------------------------------
  Future<void> _pilihKategori() async {
    final hasil = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(top: 20, bottom: 12),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text('Pilih Kategori', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            ),
            ListTile(
              title: const Text('Semua kategori'),
              trailing: _kategoriFilterId == null ? const Icon(Icons.check, color: kBlue) : null,
              onTap: () => Navigator.pop(ctx, ''),
            ),
            ..._semuaKategori.map((k) => ListTile(
                  title: Text(k.namaKategori),
                  subtitle: Text(k.jenis == 'masuk' ? 'Pemasukan' : 'Pengeluaran'),
                  trailing: _kategoriFilterId == k.id ? const Icon(Icons.check, color: kBlue) : null,
                  onTap: () => Navigator.pop(ctx, k.id),
                )),
          ],
        ),
      ),
    );
    if (hasil == null) return;
    setState(() {
      if (hasil.isEmpty) {
        _kategoriFilterId = null;
        _kategoriFilterNama = null;
      } else {
        _kategoriFilterId = hasil;
        _kategoriFilterNama = _semuaKategori.firstWhere((k) => k.id == hasil).namaKategori;
      }
    });
    _loadData();
  }

  Future<void> _pilihRentang() async {
    final hasil = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDateRange: _rentang,
      helpText: 'Pilih rentang tanggal',
      saveText: 'Terapkan',
    );
    if (hasil == null) return;
    setState(() => _rentang = hasil);
    _loadData();
  }

  void _resetFilterLanjut() {
    setState(() {
      _kategoriFilterId = null;
      _kategoriFilterNama = null;
      _rentang = null;
    });
    _loadData();
  }

  String _labelRentang() {
    final r = _rentang!;
    String f(DateTime d) => '${d.day} ${_bulan[d.month - 1]} ${d.year}';
    return '${f(r.start)} - ${f(r.end)}';
  }

  // Chip kecil untuk filter lanjutan (gaya sama dengan chip Semua/Pemasukan/Pengeluaran)
  Widget _chipFilter({
    required IconData ikon,
    required String label,
    required bool aktif,
    required VoidCallback onTap,
    bool panah = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: aktif ? kBlueSoft : Colors.white,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: aktif ? kBlue : const Color(0xFFDADCE0), width: 1.2),
        ),
        child: Row(
          children: [
            Icon(ikon, size: 18, color: aktif ? kBlueDark : kSubtitle),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: aktif ? FontWeight.w600 : FontWeight.w500,
                color: aktif ? kBlueDark : kSubtitle,
              ),
            ),
            if (panah) Icon(Icons.arrow_drop_down, size: 22, color: aktif ? kBlueDark : kSubtitle),
          ],
        ),
      ),
    );
  }

  // ----------------------------------------------------------
  // Edit transaksi (ketuk kartu transaksi)
  // ----------------------------------------------------------
  Future<void> _edit(Transaksi t) async {
    if (t.id == null) return;
    final awal = TransaksiAwal(
      id: t.id!,
      judul: t.judul,
      isPemasukan: t.isPemasukan,
      jumlah: t.jumlah,
      kategoriId: t.kategoriId,
      anggotaId: t.anggotaId,
      keterangan: t.catatan,
      tanggal: t.waktu,
      bulanKas: t.bulanKasList,
      bukti: t.buktiLama,
    );

    final hasil = await showTambahTransaksiSheet(context, awal: awal);
    if (hasil == null || !mounted) return;

    void pesan(String teks, Color warna) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(teks), backgroundColor: warna));
    }

    if (hasil.jumlah <= 0) {
      pesan('Nominal harus lebih dari 0', Colors.red);
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: kBlue)),
    );

    // 1) Perbarui data utama
    final err = await _service.updateTransaction(
      id: t.id!,
      judul: hasil.judul.isEmpty ? 'Tanpa judul' : hasil.judul,
      nominal: hasil.jumlah,
      isPemasukan: hasil.isPemasukan,
      kategoriId: hasil.kategoriId,
      anggotaId: hasil.anggotaId,
      catatan: hasil.keterangan.isEmpty ? null : hasil.keterangan,
      tanggal: hasil.tanggal,
    );
    if (err != null) {
      if (!mounted) return;
      Navigator.pop(context); // tutup loading
      pesan(err, Colors.red);
      return;
    }

    // 2) Bulan uang kas: hapus yang lama lalu simpan yang baru (hanya jika berubah)
    final lama = t.bulanKasList;
    final baru = hasil.bulanKas;
    final kasBerubah = hasil.anggotaId != t.anggotaId ||
        lama.length != baru.length ||
        !lama.toSet().containsAll(baru);
    String? errKas;
    if (kasBerubah && (lama.isNotEmpty || baru.isNotEmpty)) {
      await _kasService.hapusByTransaksi(t.id!);
      if (baru.isNotEmpty && hasil.anggotaId != null) {
        errKas = await _kasService.simpan(transaksiId: t.id!, anggotaId: hasil.anggotaId!, bulan: baru);
        if (errKas != null && lama.isNotEmpty && t.anggotaId != null) {
          // gagal -> kembalikan bulan lama supaya status kas tidak hilang
          await _kasService.simpan(transaksiId: t.id!, anggotaId: t.anggotaId!, bulan: lama);
        }
      }
    }

    // 3) Bukti: buang yang dihapus, unggah yang baru
    String? errBukti;
    for (final id in hasil.buktiDihapus) {
      final url = t.buktiLama.where((b) => b.id == id).map((b) => b.url).firstOrNull ?? '';
      final e = await _service.hapusBukti(buktiId: id, url: url);
      if (e != null) errBukti = e;
    }
    for (final pick in hasil.buktiPicks) {
      final e = await _service.uploadBukti(transaksiId: t.id!, bytes: pick.bytes, fileName: pick.fileName);
      if (e != null) errBukti = e;
    }

    if (!mounted) return;
    Navigator.pop(context); // tutup loading
    await _loadData();
    if (!mounted) return;

    if (errKas != null) {
      pesan('Data tersimpan, tetapi bulan uang kas gagal diubah: $errKas', Colors.orange);
    } else if (errBukti != null) {
      pesan('Data tersimpan, tetapi ada bukti yang bermasalah: $errBukti', Colors.orange);
    } else {
      pesan('Transaksi berhasil diperbarui', Colors.green);
    }
  }

  Future<void> _lihatBukti(Transaksi t) async {
    if (t.id == null) return;
    final urls = await _service.getBuktiByTransaksi(t.id!);
    if (!mounted) return;
    if (urls.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Transaksi ini tidak punya bukti')),
      );
      return;
    }
    Navigator.push(context, MaterialPageRoute(builder: (_) => BuktiViewerScreen(urlFoto: urls)));
  }

  @override
  Widget build(BuildContext context) {
    // Ambil list yang sudah diurutkan
    final items = _tampil;

    return Scaffold(
      backgroundColor: Colors.white,

      // ---------- ISI HALAMAN ----------
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Judul besar di atas
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 24, 24, 0),
              child: Text(
                'Semua Transaksi',
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  color: Colors.black,
                  height: 1.1,
                ),
              ),
            ),

            const SizedBox(height: 18),

            // ---------- FILTER CHIPS ----------
            // Scroll horizontal agar muat di layar kecil
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  // Chip "Semua"
                  GestureDetector(
                    onTap: () {
                      // Ubah filter menjadi "semua"
                      setState(() {
                        _filter = FilterTransaksi.semua;
                      });
                      // Ambil data ulang
                      _loadData();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 26,
                        vertical: 13,
                      ),
                      decoration: BoxDecoration(
                        // Biru muda jika dipilih, putih jika tidak
                        color: _filter == FilterTransaksi.semua
                            ? kBlueSoft
                            : Colors.white,
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(
                          color: _filter == FilterTransaksi.semua
                              ? kBlue
                              : const Color(0xFFDADCE0),
                          width: 1.2,
                        ),
                      ),
                      child: Text(
                        'Semua',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: _filter == FilterTransaksi.semua
                              ? FontWeight.w600
                              : FontWeight.w500,
                          color: _filter == FilterTransaksi.semua
                              ? kBlueDark
                              : kSubtitle,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(width: 12),

                  // Chip "Pemasukan"
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _filter = FilterTransaksi.pemasukan;
                      });
                      _loadData();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 26,
                        vertical: 13,
                      ),
                      decoration: BoxDecoration(
                        color: _filter == FilterTransaksi.pemasukan
                            ? kBlueSoft
                            : Colors.white,
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(
                          color: _filter == FilterTransaksi.pemasukan
                              ? kBlue
                              : const Color(0xFFDADCE0),
                          width: 1.2,
                        ),
                      ),
                      child: Text(
                        'Pemasukan',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: _filter == FilterTransaksi.pemasukan
                              ? FontWeight.w600
                              : FontWeight.w500,
                          color: _filter == FilterTransaksi.pemasukan
                              ? kBlueDark
                              : kSubtitle,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(width: 12),

                  // Chip "Pengeluaran"
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _filter = FilterTransaksi.pengeluaran;
                      });
                      _loadData();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 26,
                        vertical: 13,
                      ),
                      decoration: BoxDecoration(
                        color: _filter == FilterTransaksi.pengeluaran
                            ? kBlueSoft
                            : Colors.white,
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(
                          color: _filter == FilterTransaksi.pengeluaran
                              ? kBlue
                              : const Color(0xFFDADCE0),
                          width: 1.2,
                        ),
                      ),
                      child: Text(
                        'Pengeluaran',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: _filter == FilterTransaksi.pengeluaran
                              ? FontWeight.w600
                              : FontWeight.w500,
                          color: _filter == FilterTransaksi.pengeluaran
                              ? kBlueDark
                              : kSubtitle,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // ---------- FILTER LANJUTAN: kategori & rentang tanggal ----------
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  _chipFilter(
                    ikon: Icons.category_outlined,
                    label: _kategoriFilterNama ?? 'Semua kategori',
                    aktif: _kategoriFilterId != null,
                    panah: true,
                    onTap: _pilihKategori,
                  ),
                  const SizedBox(width: 10),
                  _chipFilter(
                    ikon: Icons.calendar_today_outlined,
                    label: _rentang == null ? 'Semua tanggal' : _labelRentang(),
                    aktif: _rentang != null,
                    onTap: _pilihRentang,
                  ),
                  if (_adaFilterLanjut) ...[
                    const SizedBox(width: 6),
                    TextButton(onPressed: _resetFilterLanjut, child: const Text('Reset')),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                'Ketuk transaksi untuk mengubah • geser ke kiri untuk menghapus',
                style: TextStyle(fontSize: 12, color: kSubtitle),
              ),
            ),
            const SizedBox(height: 10),

            // ---------- DAFTAR TRANSAKSI ----------
            Expanded(
              child: _isLoading
                  // Jika sedang loading -> tampilkan spinner
                  ? const Center(child: CircularProgressIndicator())
                  : items.isEmpty
                  // Jika data kosong -> tampilkan teks
                  ? Center(
                      child: Text(
                        (_adaFilterLanjut || _filter != FilterTransaksi.semua)
                            ? 'Tidak ada transaksi yang cocok dengan filter'
                            : 'Belum ada transaksi',
                        style: const TextStyle(color: kSubtitle, fontSize: 16),
                      ),
                    )
                  // Jika ada data -> tampilkan ListView
                  : RefreshIndicator(
                      // Pull ke bawah untuk refresh
                      onRefresh: _loadData,
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 110),
                        itemCount: items.length,
                        itemBuilder: (context, i) {
                          // Ambil 1 transaksi
                          final t = items[i];

                          // Tentukan warna & ikon berdasarkan kategori
                          IconData ikon;
                          Color warnaIkon;
                          Color warnaBg;

                          if (t.kategori == 'Uang Kas') {
                            ikon = Icons.account_balance_wallet;
                            warnaIkon = kBlue;
                            warnaBg = kBlueSoft;
                          } else if (t.kategori == 'Donasi') {
                            ikon = Icons.volunteer_activism;
                            warnaIkon = kBlue;
                            warnaBg = kBlueSoft;
                          } else if (t.kategori == 'Kebutuhan Kelas') {
                            ikon = Icons.menu_book;
                            warnaIkon = kCatBlue;
                            warnaBg = kCatBlueSoft;
                          } else if (t.kategori == 'Event') {
                            ikon = Icons.celebration;
                            warnaIkon = kCatBlue;
                            warnaBg = kCatBlueSoft;
                          } else if (t.kategori == 'Kesenangan') {
                            ikon = Icons.emoji_emotions;
                            warnaIkon = kOrange;
                            warnaBg = kOrangeSoft;
                          } else if (t.isPemasukan) {
                            // Default pemasukan
                            ikon = Icons.account_balance_wallet;
                            warnaIkon = kBlue;
                            warnaBg = kBlueSoft;
                          } else {
                            // Default pengeluaran
                            ikon = Icons.shopping_bag;
                            warnaIkon = kRed;
                            warnaBg = kRedSoft;
                          }

                          // Warna nominal: biru jika masuk, merah jika keluar
                          final warnaJumlah = t.isPemasukan ? kBlue : kRed;
                          // Tanda + atau -
                          final tanda = t.isPemasukan ? '+' : '-';

                          // Dismissible = item bisa di-swipe untuk hapus
                          return Dismissible(
                            // Key unik wajib untuk Dismissible
                            key: Key(t.id ?? i.toString()),
                            // Hanya boleh swipe dari kanan ke kiri
                            direction: DismissDirection.endToStart,
                            // Tampilan saat di-swipe
                            background: Container(
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 20),
                              color: Colors.red,
                              child: const Icon(
                                Icons.delete,
                                color: Colors.white,
                              ),
                            ),

                            // Dipanggil sebelum item benar-benar dihapus
                            confirmDismiss: (direction) async {
                              // Harus punya id dari database
                              if (t.id == null) return false;
                              // Minta konfirmasi dulu supaya catatan kas tidak terhapus tak sengaja
                              final yakin = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: const Text('Hapus transaksi?'),
                                  content: Text(
                                    '"${t.judul}" akan dihapus'
                                    '${t.ringkasBulanKas != null ? ', dan bulan uang kas yang tercatat (${t.ringkasBulanKas}) kembali berstatus belum bayar' : ''}.',
                                  ),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx, true),
                                      child: const Text('Hapus', style: TextStyle(color: Colors.red)),
                                    ),
                                  ],
                                ),
                              );
                              if (yakin != true) return false;
                              // Panggil service untuk hapus di Supabase
                              final error = await _service.deleteTransaction(
                                t.id!,
                              );
                              if (error == null) {
                                // Sukses -> hilangkan dari list
                                return true;
                              }
                              // Gagal -> batalkan swipe & tampilkan pesan
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(error),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              }
                              return false;
                            },

                            // Setelah animasi swipe selesai
                            onDismissed: (direction) {
                              setState(() {
                                _data.removeWhere((e) => e.id == t.id);
                              });
                            },

                            // Tampilan 1 item transaksi (ketuk = edit)
                            child: GestureDetector(
                             onTap: () => _edit(t),
                             child: Container(
                              margin: const EdgeInsets.only(bottom: 16),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 18,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(18),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.08),
                                    blurRadius: 14,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Row(
                                children: [
                                  // Ikon lingkaran di kiri
                                  Container(
                                    width: 60,
                                    height: 60,
                                    decoration: BoxDecoration(
                                      color: warnaBg,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      ikon,
                                      color: warnaIkon,
                                      size: 30,
                                    ),
                                  ),

                                  const SizedBox(width: 16),

                                  // Teks di tengah (judul, kategori, tanggal)
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        // Judul
                                        Text(
                                          t.judul,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.black,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        // Jenis + kategori
                                        Text(
                                          '${t.isPemasukan ? 'Pemasukan' : 'Pengeluaran'} • ${t.kategori}'
                                          '${t.anggotaNama != null ? ' • ${t.anggotaNama}' : ''}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 15,
                                            color: kSubtitle,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        // Tanggal
                                        Text(
                                          _waktuText(t.waktu),
                                          style: const TextStyle(
                                            fontSize: 15,
                                            color: kSubtitle,
                                          ),
                                        ),
                                        if (t.ringkasBulanKas != null) ...[
                                          const SizedBox(height: 4),
                                          Text(
                                            'Bayar kas: ${t.ringkasBulanKas}',
                                            style: const TextStyle(fontSize: 13, color: kBlue),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),

                                  const SizedBox(width: 8),

                                  // Nominal + indikator bukti di kanan
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        '$tanda${_rupiah(t.jumlah)}',
                                        style: TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.w700,
                                          color: warnaJumlah,
                                        ),
                                      ),
                                      if (t.jumlahBukti > 0) ...[
                                        const SizedBox(height: 6),
                                        InkWell(
                                          onTap: () => _lihatBukti(t),
                                          child: Row(
                                            children: [
                                              const Icon(Icons.attach_file, size: 14, color: kBlue),
                                              Text(' ${t.jumlahBukti}',
                                                  style: const TextStyle(fontSize: 12, color: kBlue)),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
