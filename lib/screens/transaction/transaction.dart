import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/kategori_service.dart';
import '../../services/anggota_service.dart';
import '../../services/kas_service.dart';
import '../../services/pengaturan_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/format.dart';

export '../../theme/app_colors.dart'; // supaya file yang import transaction.dart tetap kebagian warna ini

// Foto bukti disimpan sebagai bytes (bukan dart:io File),
// supaya jalan di semua platform termasuk Flutter Web.
class BuktiPick {
  final Uint8List bytes;
  final String fileName;
  const BuktiPick({required this.bytes, required this.fileName});
}

// 1 foto bukti yang sudah tersimpan di server (dipakai saat EDIT)
class BuktiLama {
  final String id;
  final String url;
  const BuktiLama({required this.id, required this.url});
}

// Data awal transaksi yang akan diedit
class TransaksiAwal {
  final String id;
  final String judul;
  final bool isPemasukan;
  final int jumlah;
  final String? kategoriId;
  final String? anggotaId;
  final String keterangan;
  final DateTime tanggal;
  final List<BulanKas> bulanKas;
  final List<BuktiLama> bukti;
  const TransaksiAwal({
    required this.id,
    required this.judul,
    required this.isPemasukan,
    required this.jumlah,
    required this.kategoriId,
    required this.anggotaId,
    required this.keterangan,
    required this.tanggal,
    required this.bulanKas,
    required this.bukti,
  });
}

// ============================================================
// Data yang dikirim keluar saat tombol Simpan ditekan.
// Penyimpanan ke database & unggah bukti dilakukan di nav.dart (_tambahDariNav).
// ============================================================
class TransactionResult {
  final bool isPemasukan;
  final int jumlah;
  final String judul;
  final String keterangan;
  final String? kategoriId; // null jika "pakai kategori" dimatikan
  final String? anggotaId; // untuk pemasukan (wajib bila uang kas)
  final DateTime tanggal;
  final List<BuktiPick> buktiPicks;
  final List<BulanKas> bulanKas; // bulan yang dibayar (khusus kategori uang kas)
  final String? id; // terisi hanya saat EDIT
  final List<String> buktiDihapus; // id bukti lama yang dibuang (saat EDIT)

  TransactionResult({
    this.id,
    this.buktiDihapus = const [],
    required this.isPemasukan,
    required this.jumlah,
    required this.judul,
    required this.keterangan,
    required this.kategoriId,
    required this.anggotaId,
    required this.tanggal,
    required this.buktiPicks,
    required this.bulanKas,
  });
}

// [awal] diisi => form dibuka dalam mode EDIT
Future<TransactionResult?> showTambahTransaksiSheet(BuildContext context, {TransaksiAwal? awal}) {
  return showModalBottomSheet<TransactionResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    constraints: const BoxConstraints(maxWidth: 720),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => TambahTransaksiSheet(awal: awal),
  );
}

class RupiahFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    String digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    digits = digits.replaceFirst(RegExp(r'^0+'), '');
    if (digits.isEmpty) digits = '0';

    final buffer = StringBuffer();
    for (int i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write('.');
      buffer.write(digits[i]);
    }
    final text = 'Rp $buffer';
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  }
}

class TambahTransaksiSheet extends StatefulWidget {
  final TransaksiAwal? awal;
  const TambahTransaksiSheet({super.key, this.awal});

  @override
  State<TambahTransaksiSheet> createState() => _TambahTransaksiSheetState();
}

class _TambahTransaksiSheetState extends State<TambahTransaksiSheet> {
  bool _isPemasukan = true;
  bool _pakaiKategori = true;

  final _jumlahController = TextEditingController(text: 'Rp 0');
  final _judulController = TextEditingController();
  final _keteranganController = TextEditingController();

  Kategori? _kategoriTerpilih;
  Anggota? _anggotaTerpilih;
  DateTime _tanggal = DateTime.now();
  final List<BuktiPick> _buktiPicks = [];

  // ---- khusus uang kas ----
  int _tahunTampil = DateTime.now().year;
  final Set<BulanKas> _bulanDipilih = {}; // bulan yang akan dibayar sekarang
  Set<BulanKas> _bulanLunas = {}; // bulan yang sudah pernah dibayar anggota ini
  bool _memuatLunas = false;

  final _kategoriService = KategoriService();
  final _anggotaService = AnggotaService();
  final _kasService = KasService();
  List<Kategori> _semuaKategori = [];
  List<Anggota> _daftarAnggota = [];
  bool _loadingOpsi = true;

  String? _pesanError;

  int _iuran = 0; // iuran per bulan dari Pengaturan Kelas (0 = belum diatur)

  // ---- khusus mode edit ----
  List<BuktiLama> _buktiLama = [];
  final List<String> _buktiDihapus = [];
  bool get _modeEdit => widget.awal != null;

  // Kategori yang sesuai jenis transaksi saat ini (pemasukan / pengeluaran)
  List<Kategori> get _kategoriTersedia =>
      _semuaKategori.where((k) => k.jenis == (_isPemasukan ? 'masuk' : 'keluar')).toList();

  // Mode uang kas: pemasukan + kategori bertanda uang kas dipilih
  bool get _modeUangKas => _isPemasukan && _pakaiKategori && (_kategoriTerpilih?.adalahUangKas ?? false);

  @override
  void initState() {
    super.initState();
    final a = widget.awal;
    if (a != null) {
      _isPemasukan = a.isPemasukan;
      _pakaiKategori = a.kategoriId != null;
      _jumlahController.text = rupiah(a.jumlah);
      _judulController.text = a.judul;
      _keteranganController.text = a.keterangan;
      _tanggal = a.tanggal;
      _buktiLama = [...a.bukti];
      if (a.bulanKas.isNotEmpty) _tahunTampil = a.bulanKas.first.tahun;
    }
    _muatOpsi();
  }

  Future<void> _muatOpsi() async {
    final a = widget.awal;
    final semua = await _kategoriService.getAll();
    // Saat edit, kategori transaksi ini tetap muncul walau sudah dinonaktifkan
    final kategori = semua.where((k) => k.kategoriAktif || k.id == a?.kategoriId).toList();
    final anggota = await _anggotaService.getAll();
    final peng = await PengaturanService().get();
    if (!mounted) return;
    _iuran = peng.nominalIuran;

    Kategori? kategoriAwal;
    Anggota? anggotaAwal;
    if (a != null) {
      for (final k in kategori) {
        if (k.id == a.kategoriId) kategoriAwal = k;
      }
      for (final m in anggota) {
        if (m.id == a.anggotaId) anggotaAwal = m;
      }
    }

    setState(() {
      _semuaKategori = kategori;
      _daftarAnggota = anggota;
      _kategoriTerpilih = kategoriAwal;
      _anggotaTerpilih = anggotaAwal;
      _loadingOpsi = false;
    });

    if (a != null && anggotaAwal != null && a.bulanKas.isNotEmpty) {
      await _muatBulanEdit(anggotaAwal, a);
    }
  }

  // Mode edit uang kas: bulan milik transaksi ini ditampilkan sebagai "terpilih", bukan "lunas"
  Future<void> _muatBulanEdit(Anggota ang, TransaksiAwal a) async {
    setState(() => _memuatLunas = true);
    final lunas = await _kasService.getBulanLunas(ang.id, kecualiTransaksiId: a.id);
    if (!mounted) return;
    setState(() {
      _bulanLunas = lunas;
      _bulanDipilih
        ..clear()
        ..addAll(a.bulanKas);
      _memuatLunas = false;
    });
  }

  @override
  void dispose() {
    _jumlahController.dispose();
    _judulController.dispose();
    _keteranganController.dispose();
    super.dispose();
  }

  // Dipanggil saat anggota dipilih: ambil bulan-bulan yang sudah lunas
  Future<void> _pilihAnggota(Anggota? a) async {
    setState(() {
      _anggotaTerpilih = a;
      _bulanDipilih.clear();
      _bulanLunas = {};
      _pesanError = null;
    });
    if (a == null) return;

    setState(() => _memuatLunas = true);
    final lunas = await _kasService.getBulanLunas(a.id, kecualiTransaksiId: widget.awal?.id);
    if (!mounted || _anggotaTerpilih?.id != a.id) return;
    setState(() {
      _bulanLunas = lunas;
      _memuatLunas = false;
    });
  }

  // Uang kas: nominal = iuran per bulan x jumlah bulan dipilih (tetap bisa diubah manual)
  void _isiNominalOtomatis() {
    if (_iuran <= 0 || _bulanDipilih.isEmpty) return;
    _jumlahController.text = rupiah(_iuran * _bulanDipilih.length);
  }

  Future<void> _pilihTanggal() async {
    FocusScope.of(context).unfocus();
    final hasil = await showDatePicker(
      context: context,
      initialDate: _tanggal,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (hasil != null) setState(() => _tanggal = hasil);
  }

  Future<void> _tambahBukti() async {
    final sumber = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera, color: kBlue),
              title: const Text('Ambil dari Kamera'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: kBlue),
              title: const Text('Pilih dari Galeri'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (sumber == null) return;

    final picker = ImagePicker();
    final file = await picker.pickImage(source: sumber, imageQuality: 70);
    if (file != null) {
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() => _buktiPicks.add(BuktiPick(bytes: bytes, fileName: file.name)));
    }
  }

  void _simpan() {
    final jumlah = int.tryParse(_jumlahController.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

    // ---- Validasi (ditampilkan di dalam form supaya isian tidak hilang) ----
    if (jumlah <= 0) {
      setState(() => _pesanError = 'Nominal harus lebih dari 0');
      return;
    }
    if (_modeUangKas) {
      if (_anggotaTerpilih == null) {
        setState(() => _pesanError = 'Pilih anggota yang membayar uang kas');
        return;
      }
      if (_bulanDipilih.isEmpty) {
        setState(() => _pesanError = 'Pilih minimal satu bulan yang dibayar');
        return;
      }
    }

    final bulanUrut = _modeUangKas
        ? (_bulanDipilih.toList()..sort((a, b) => urutanBulan(a).compareTo(urutanBulan(b))))
        : <BulanKas>[];

    // Judul otomatis untuk uang kas bila dikosongkan
    String judul = _judulController.text.trim();
    if (judul.isEmpty && _modeUangKas) judul = 'Uang kas ${_anggotaTerpilih!.nama}';

    Navigator.pop(
      context,
      TransactionResult(
        isPemasukan: _isPemasukan,
        jumlah: jumlah,
        judul: judul,
        keterangan: _keteranganController.text.trim(),
        kategoriId: _pakaiKategori ? _kategoriTerpilih?.id : null,
        anggotaId: _isPemasukan ? _anggotaTerpilih?.id : null,
        tanggal: _tanggal,
        buktiPicks: _buktiPicks,
        bulanKas: bulanUrut,
        id: widget.awal?.id,
        buktiDihapus: _buktiDihapus,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final tanggalText = '${_tanggal.day} ${namaBulanPanjang[_tanggal.month - 1]} ${_tanggal.year}';

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ========== HEADER ==========
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 6, offset: const Offset(0, 2))],
            ),
            child: Column(
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 10),
                  width: 40, height: 4,
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                ),
                SizedBox(
                  height: 56,
                  child: Row(
                    children: [
                      IconButton(icon: const Icon(Icons.arrow_back, color: kTextDark), onPressed: () => Navigator.pop(context)),
                      const SizedBox(width: 4),
                      Text(_modeEdit ? 'Edit Transaksi' : 'Tambah Transaksi',
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: kTextDark)),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ========== ISI FORM ==========
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ---- Pilihan Pemasukan / Pengeluaran ----
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F4F8),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        Expanded(child: _tabToggle('Pemasukan', _isPemasukan, () => setState(() {
                          _isPemasukan = true;
                          _kategoriTerpilih = null;
                          _pesanError = null;
                        }))),
                        Expanded(child: _tabToggle('Pengeluaran', !_isPemasukan, () => setState(() {
                          _isPemasukan = false;
                          _kategoriTerpilih = null;
                          _anggotaTerpilih = null;
                          _bulanDipilih.clear();
                          _bulanLunas = {};
                          _pesanError = null;
                        }))),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ---- Nominal ----
                  TextField(
                    controller: _jumlahController,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    inputFormatters: [RupiahFormatter()],
                    style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w700, color: kBlue),
                    cursorColor: kBlue,
                    decoration: const InputDecoration(border: InputBorder.none, isDense: true),
                  ),
                  Center(child: Container(width: 200, height: 1.5, color: kBlueLight)),
                  const SizedBox(height: 20),

                  // ---- Judul ----
                  _kotakInput(
                    child: TextField(
                      controller: _judulController,
                      decoration: InputDecoration(
                        hintText: _modeUangKas ? 'Judul (boleh kosong, otomatis "Uang kas ...")' : 'Judul transaksi (mis. Beli spidol)',
                        border: InputBorder.none, isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // ---- Pakai kategori? ----
                  _kotakInput(
                    child: Row(
                      children: [
                        const Expanded(child: Text('Pakai kategori?', style: TextStyle(fontSize: 15, color: kTextDark))),
                        Switch(
                          value: _pakaiKategori,
                          activeThumbColor: kBlue,
                          onChanged: (v) => setState(() {
                            _pakaiKategori = v;
                            if (!v) {
                              _kategoriTerpilih = null;
                              _bulanDipilih.clear();
                            }
                          }),
                        ),
                      ],
                    ),
                  ),

                  // ---- Pilihan kategori (sesuai jenis transaksi) ----
                  if (_pakaiKategori) ...[
                    const SizedBox(height: 12),
                    _kotakInput(
                      child: _loadingOpsi
                          ? const Padding(padding: EdgeInsets.all(4), child: LinearProgressIndicator(color: kBlue))
                          : DropdownButtonHideUnderline(
                              child: DropdownButton<Kategori>(
                                isExpanded: true,
                                hint: Text(_isPemasukan ? 'Pilih kategori pemasukan' : 'Pilih kategori pengeluaran'),
                                value: _kategoriTerpilih,
                                items: _kategoriTersedia
                                    .map((k) => DropdownMenuItem(value: k, child: Text(k.namaKategori)))
                                    .toList(),
                                onChanged: (v) => setState(() {
                                  _kategoriTerpilih = v;
                                  _bulanDipilih.clear();
                                  _pesanError = null;
                                }),
                              ),
                            ),
                    ),
                    if (!_loadingOpsi && _kategoriTersedia.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 6, left: 4),
                        child: Text('Belum ada kategori aktif untuk jenis ini. Tambah lewat menu Kategori di Beranda.',
                            style: TextStyle(fontSize: 12, color: kTextGrey)),
                      ),
                  ],

                  // ---- Anggota (khusus pemasukan) ----
                  if (_isPemasukan) ...[
                    const SizedBox(height: 12),
                    _kotakInput(
                      child: _loadingOpsi
                          ? const Padding(padding: EdgeInsets.all(4), child: LinearProgressIndicator(color: kBlue))
                          : DropdownButtonHideUnderline(
                              child: DropdownButton<Anggota>(
                                isExpanded: true,
                                hint: Text(_modeUangKas
                                    ? 'Pilih anggota yang membayar (wajib)'
                                    : 'Dari anggota (opsional)'),
                                value: _anggotaTerpilih,
                                items: _daftarAnggota
                                    .map((a) => DropdownMenuItem(value: a, child: Text(a.nama)))
                                    .toList(),
                                onChanged: _pilihAnggota,
                              ),
                            ),
                    ),
                    if (!_loadingOpsi && _daftarAnggota.isEmpty && _modeUangKas)
                      const Padding(
                        padding: EdgeInsets.only(top: 6, left: 4),
                        child: Text('Belum ada anggota. Tambah dulu lewat menu Anggota di Beranda.',
                            style: TextStyle(fontSize: 12, color: kTextGrey)),
                      ),
                  ],

                  // ---- Pilihan bulan (khusus uang kas) ----
                  if (_modeUangKas) ...[
                    const SizedBox(height: 16),
                    _bagianPilihBulan(),
                  ],

                  const SizedBox(height: 12),

                  // ---- Tanggal ----
                  _kotakInput(
                    child: InkWell(
                      onTap: _pilihTanggal,
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today_outlined, color: kBlue, size: 20),
                          const SizedBox(width: 10),
                          Text(tanggalText, style: const TextStyle(fontSize: 15, color: kTextDark)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // ---- Catatan ----
                  _kotakInput(
                    child: TextField(
                      controller: _keteranganController,
                      maxLines: 2,
                      decoration: const InputDecoration(hintText: 'Catatan (opsional)', border: InputBorder.none, isDense: true),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ---- Bukti ----
                  const Text('Bukti Transaksi', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: kTextDark)),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10, runSpacing: 10,
                    children: [
                      // bukti yang sudah tersimpan (mode edit)
                      ..._buktiLama.map((b) => Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.network(
                                  b.url,
                                  width: 76,
                                  height: 76,
                                  fit: BoxFit.cover,
                                  errorBuilder: (ctx, err, st) => Container(
                                    width: 76,
                                    height: 76,
                                    color: const Color(0xFFF1F4F8),
                                    child: const Icon(Icons.broken_image, color: Colors.grey),
                                  ),
                                ),
                              ),
                              Positioned(
                                top: -6, right: -6,
                                child: IconButton(
                                  icon: const Icon(Icons.cancel, color: Colors.red, size: 20),
                                  onPressed: () => setState(() {
                                    _buktiDihapus.add(b.id);
                                    _buktiLama.remove(b);
                                  }),
                                ),
                              ),
                            ],
                          )),
                      ..._buktiPicks.asMap().entries.map((e) => Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.memory(e.value.bytes, width: 76, height: 76, fit: BoxFit.cover),
                              ),
                              Positioned(
                                top: -6, right: -6,
                                child: IconButton(
                                  icon: const Icon(Icons.cancel, color: Colors.red, size: 20),
                                  onPressed: () => setState(() => _buktiPicks.removeAt(e.key)),
                                ),
                              ),
                            ],
                          )),
                      InkWell(
                        onTap: _tambahBukti,
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          width: 76, height: 76,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F4F8),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: const Icon(Icons.add_a_photo_outlined, color: kBlue),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // ---- Pesan kesalahan ----
                  if (_pesanError != null)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFDE8E8),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(_pesanError!, style: const TextStyle(color: Color(0xFFA3201B))),
                    ),

                  // ---- Tombol Simpan ----
                  SizedBox(
                    width: double.infinity, height: 52,
                    child: ElevatedButton(
                      onPressed: _simpan,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kBlue,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Text(_modeEdit ? 'Simpan Perubahan' : 'Simpan',
                          style: const TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Bagian "Bayar untuk bulan apa saja?" (hanya muncul untuk kategori uang kas)
  Widget _bagianPilihBulan() {
    if (_anggotaTerpilih == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: const Color(0xFFE3F2FB), borderRadius: BorderRadius.circular(12)),
        child: const Text('Kategori uang kas: pilih dulu anggota yang membayar, lalu pilih bulan yang dibayar.',
            style: TextStyle(fontSize: 13, color: kBlueDarkBrand)),
      );
    }

    final bulanUrut = _bulanDipilih.toList()..sort((a, b) => urutanBulan(a).compareTo(urutanBulan(b)));

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FAFD),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD6E9FA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Bayar untuk bulan apa saja? (${_anggotaTerpilih!.nama})',
              style: const TextStyle(fontWeight: FontWeight.w600, color: kTextDark)),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => setState(() => _tahunTampil--)),
              Text('$_tahunTampil', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => setState(() => _tahunTampil++)),
            ],
          ),
          if (_memuatLunas)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: LinearProgressIndicator(color: kBlue),
            )
          else
            GridView.count(
              crossAxisCount: 4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 2.1,
              children: List.generate(12, (i) {
                final BulanKas b = (tahun: _tahunTampil, bulan: i + 1);
                final lunas = _bulanLunas.contains(b);
                final dipilih = _bulanDipilih.contains(b);

                Color latar = const Color(0xFFEEF1F5);
                Color teks = kTextDark;
                if (lunas) {
                  latar = const Color(0xFFD9F2E3);
                  teks = const Color(0xFF1B6B3A);
                } else if (dipilih) {
                  latar = kBlue;
                  teks = Colors.white;
                }

                return InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: lunas
                      ? null
                      : () => setState(() {
                            dipilih ? _bulanDipilih.remove(b) : _bulanDipilih.add(b);
                            _pesanError = null;
                            _isiNominalOtomatis();
                          }),
                  child: Container(
                    decoration: BoxDecoration(color: latar, borderRadius: BorderRadius.circular(10)),
                    alignment: Alignment.center,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (lunas) Icon(Icons.check, size: 14, color: teks),
                        Text(namaBulanSingkat[i], style: TextStyle(color: teks, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                );
              }),
            ),
          const SizedBox(height: 8),
          Text(
            bulanUrut.isEmpty
                ? 'Belum ada bulan dipilih. Bulan berwarna hijau sudah lunas.${_iuran > 0 ? ' Iuran ${rupiah(_iuran)}/bulan.' : ''}'
                : '${bulanUrut.length} bulan dipilih: ${bulanUrut.map(labelBulan).join(', ')}',
            style: const TextStyle(fontSize: 12, color: kTextGrey),
          ),
        ],
      ),
    );
  }

  Widget _tabToggle(String label, bool aktif, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: aktif ? kBlue : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.center,
        child: Text(label, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: aktif ? Colors.white : kTextDark)),
      ),
    );
  }

  Widget _kotakInput({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 10, offset: const Offset(0, 2))],
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: child,
    );
  }
}
