import 'package:flutter/material.dart';
import 'package:moneynotes/screens/login_page/login.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/date_symbol_data_local.dart';


Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: 'https://wswfplrzodehzktjtrgk.supabase.co',
    anonKey: 'sb_publishable_aAi2XmwsiKaME-0xjnluMQ_ImBO1hpS',
  );

  // Wajib, supaya DateFormat('dd MMM yyyy', 'id_ID') di export_laporan_screen.dart
  // dan pdf_service.dart tidak crash (format tanggal Bahasa Indonesia).
  await initializeDateFormatting('id_ID', null);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SakuKelas',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0D8BF2)),
        useMaterial3: true,
      ),
      home: const Login(),
    );
  }
}
