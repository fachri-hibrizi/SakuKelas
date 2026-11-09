import 'package:flutter/material.dart';
import '../../services/anggota_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/format.dart';

class KelolaAnggotaScreen extends StatefulWidget {
  const KelolaAnggotaScreen({super.key});

  @override
  State<KelolaAnggotaScreen> createState() => _KelolaAnggotaScreenState();
}

class _KelolaAnggotaScreenState extends State<KelolaAnggotaScreen> {
  final _service = AnggotaService();
  List<Anggota> _anggota = [];
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
      _anggota = data;
      _loading = false;
    });
  }

  void _pesan(String teks) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(teks)));
  }

  // Dialog tambah (awal == null) atau ubah anggota.
  // "Mulai iuran" dipakai untuk murid pindahan / anggota baru: bulan sebelumnya
  // tidak dihitung sebagai tunggakan.
  Future<void> _formAnggota({Anggota? awal}) async {
    final controller = TextEditingController(text: awal?.nama ?? '');
    DateTime? mulai = awal?.mulaiBayar;

    final hasil = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: Text(awal == null ? 'Tambah Anggota' : 'Ubah Anggota'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: controller,
                decoration: const InputDecoration(hintText: 'Nama siswa'),
                autofocus: true,
              ),
              const SizedBox(height: 16),
              const Text('Mulai iuran kas', style: TextStyle(fontSize: 12, color: kTextGrey)),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      mulai == null ? 'Sejak awal kas kelas' : labelBulan((tahun: mulai!.year, bulan: mulai!.month)),
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      final d = await showDatePicker(
                        context: ctx,
                        initialDate: mulai ?? DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                        helpText: 'Pilih bulan mulai iuran',
                      );
                      if (d != null) setDialog(() => mulai = DateTime(d.year, d.month, 1));
                    },
                    child: const Text('Ubah'),
                  ),
                  if (mulai != null)
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => setDialog(() => mulai = null),
                    ),
                ],
              ),
              const Text('Bulan sebelum ini tidak dihitung sebagai tunggakan.',
                  style: TextStyle(fontSize: 11, color: kTextGrey)),
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

    if (hasil == true) {
      final err = awal == null
          ? await _service.tambah(controller.text, mulaiBayar: mulai)
          : await _service.ubah(awal.id, controller.text, mulai);
      if (err != null) {
        _pesan(err);
      } else {
        _muat();
      }
    }
  }

  Future<void> _hapusAnggota(Anggota a) async {
    final yakin = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus Anggota'),
        content: Text('Hapus "${a.nama}" dari daftar anggota?\n\n'
            'Catatan bulan uang kas milik anggota ini ikut terhapus. '
            'Transaksinya tetap ada, tetapi tanpa nama anggota.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hapus', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (yakin == true) {
      final err = await _service.hapus(a.id);
      if (err != null) {
        _pesan(err);
      } else {
        _muat();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kelola Anggota'),
        backgroundColor: kBlue,
        foregroundColor: Colors.white,
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: kBlue,
        onPressed: () => _formAnggota(),
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kBlue))
          : _anggota.isEmpty
              ? const Center(child: Text('Belum ada anggota. Tambah dulu lewat tombol +'))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                  itemCount: _anggota.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (ctx, i) {
                    final a = _anggota[i];
                    return ListTile(
                      onTap: () => _formAnggota(awal: a),
                      leading: const CircleAvatar(
                        backgroundColor: Color(0xFFE3F2FB),
                        child: Icon(Icons.person, color: kBlue),
                      ),
                      title: Text(a.nama),
                      subtitle: a.mulaiBayar == null
                          ? null
                          : Text('Iuran mulai ${labelBulan((tahun: a.mulaiBayar!.year, bulan: a.mulaiBayar!.month))}',
                              style: const TextStyle(fontSize: 12)),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                        onPressed: () => _hapusAnggota(a),
                      ),
                    );
                  },
                ),
    );
  }
}
