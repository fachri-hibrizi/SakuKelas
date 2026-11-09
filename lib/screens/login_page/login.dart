import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:moneynotes/screens/daftar_akun/daftarAkun.dart';
import 'package:moneynotes/screens/nav.dart';
import 'package:moneynotes/widget/inputLogin.dart';
import 'package:moneynotes/services/auth_service.dart';

class Login extends StatefulWidget {
  const Login({super.key});

  @override
  State<Login> createState() => _LoginState();
}

class _LoginState extends State<Login> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscureText = true;
  bool _isLoading = false;
  final AuthService _authService = AuthService();

  Future<void> _handleLogin() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('email dan password wajib diisi')),
      );
      return;
    }

    setState(() => _isLoading = true);

    final error = await _authService.signIn(email: email, password: password);

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (error == null) {
      // Login berhasil
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const Navigation()),
      );
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), backgroundColor: Colors.red),
      );
    }
  }

  //CONTROLER
  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(top: 80),
        child: SafeArea(
          child: Column(
            children: [
              // BAGIAN LOGO (logo asli SakuKelas, bukan ikon generik lagi)
              Image.asset(
                'assets/images/logo.png',
                width: 160,
                height: 160,
              ),

              //JARAK LOGO KE TEXT JUDUL
              const SizedBox(height: 12),

              //TEXT DEKSRIPSI
              Text(
                "Buku Kas Kelas, Mudah & Transparan",
                //FONT/STYLING TEXT DESKRIPSI
                style: GoogleFonts.lato(color: Colors.grey, fontSize: 16),
              ),

              //JARAK KE TEXFIELD
              const SizedBox(height: 40),

              //JANGAN MENGUBAH APAPUN DIDALAM KODE PADDING TEXFIELD INI
              // TEXTFIELD
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 30),
                child: Column(
                  children: [
                    InputLogin(
                      label: "Email",
                      icon: Icons.email_outlined,
                      controller: _emailController,
                    ),
                    InputLogin(
                      label: "Password",
                      icon: Icons.lock_outline,
                      controller: _passwordController,
                      isPassword: true,
                      obscureText: _obscureText,
                      onToggleVisibility: () {
                        setState(() => _obscureText = !_obscureText);
                      },
                    ),
                  ],
                ),
              ),

              // Tombol Masuk
              Container(
                margin: const EdgeInsets.symmetric(
                  horizontal: 30,
                  vertical: 25,
                ),
                //LEBAR INFINITY CONTAINER
                width: double.infinity,
                height: 55,
                //WARNA CONTAINER
                decoration: BoxDecoration(
                    color: Color(0xFF0D8BF2),
                  //RADIUS CONTAINER
                  borderRadius: BorderRadius.circular(12),
                ),
                //BUTTON MENGGUNAKAN INKWELL
                child: InkWell(
                  //FUNGSI KETIKA DI KLIK
                  onTap: _isLoading ? null : _handleLogin,
                  //TEXT BUTTON AGR DI TENGAH
                  child: Center(
                    child: _isLoading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            "Masuk",
                            style: GoogleFonts.lato(
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              fontSize: 18,
                            ),
                          ),
                  ),
                ),
              ),

              // Link Daftar
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text("Belum punya akun? "),

                  //TEXT BUTTON DAFTAR
                  TextButton(
                    //FUNGSI TEXT BUTTON
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const CreateAccount(),
                        ),
                      );
                    },
                    //TEXT BUTTON
                    child: const Text(
                      "Daftar Sekarang",
                      style: TextStyle(color: Color(0xFF0D8BF2)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
