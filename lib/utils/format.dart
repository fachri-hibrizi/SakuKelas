// Fungsi bantu format yang dipakai di banyak layar & laporan PDF.
// Ditulis manual (tanpa paket intl) supaya nama bulan selalu Bahasa Indonesia
// dan tidak bergantung pada data locale.

// Satu bulan pembayaran uang kas, contoh: (tahun: 2026, bulan: 3) = Maret 2026
typedef BulanKas = ({int tahun, int bulan});

const List<String> namaBulanPanjang = [
  'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
  'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember',
];

const List<String> namaBulanSingkat = [
  'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
  'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des',
];

// 1500000 -> "Rp 1.500.000"
String rupiah(int nilai) {
  final negatif = nilai < 0;
  final angka = nilai.abs().toString();
  final buffer = StringBuffer();
  for (int i = 0; i < angka.length; i++) {
    if (i > 0 && (angka.length - i) % 3 == 0) buffer.write('.');
    buffer.write(angka[i]);
  }
  return '${negatif ? '-' : ''}Rp $buffer';
}

// 2026-03-07 -> "7 Mar 2026"
String tanggalIndo(DateTime t) => '${t.day} ${namaBulanSingkat[t.month - 1]} ${t.year}';

// (2026, 3) -> "Mar 2026"
String labelBulan(BulanKas b) => '${namaBulanSingkat[b.bulan - 1]} ${b.tahun}';

// Angka urut bulan, dipakai untuk membandingkan / mengurutkan bulan
int urutanBulan(BulanKas b) => b.tahun * 12 + b.bulan;

// Daftar semua bulan dari bulan [dari] sampai bulan [sampai] (inklusif)
List<BulanKas> daftarBulan(DateTime dari, DateTime sampai) {
  final hasil = <BulanKas>[];
  var t = DateTime(dari.year, dari.month);
  final akhir = DateTime(sampai.year, sampai.month);
  while (!t.isAfter(akhir)) {
    hasil.add((tahun: t.year, bulan: t.month));
    t = DateTime(t.year, t.month + 1);
  }
  return hasil;
}

// Format tanggal untuk dikirim ke database: "YYYY-MM-DD"
String tanggalDb(DateTime t) =>
    '${t.year.toString().padLeft(4, '0')}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
