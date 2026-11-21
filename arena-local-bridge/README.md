# Arena.ai Local Terminal & Tool Bridge (Seçenek 2B — Localhost HTTP + API Token)

Arena.ai sohbet penceresinde modelin ürettiği araç ve terminal çağrılarını (`arena-tool` bloklarını), **manuel onayınızla** yerel `127.0.0.1` sunucusu üzerinden bilgisayarınızda çalıştıran Chrome Manifest V3 eklentisidir.

Kurulum için Extension ID kopyalamaya, Registry düzenlemeye veya Native Messaging dosyası yerleştirmeye gerek yoktur.

---

## Kurulum (2 Adım)

### 1. Yerel Sunucuyu Başlatın
Bilgisayarınızda `arena-local-bridge` klasöründe işletim sisteminize göre çalıştırın:

- **Linux / macOS:**
  ```bash
  ./start.sh
  ```
- **Windows:**
  `start.bat` dosyasına çift tıklayın veya terminalden çalıştırın:
  ```bat
  start.bat
  ```

İlk çalıştırmada sunucu otomatik olarak:
- Varsayılan `http://127.0.0.1:38450` adresini açar,
- **Tam Bilgisayar Erişimi (`full_system_access: true`)** modunu hazırlar,
- Güvenli bir **API Token** üretip ekrana yazdırır.

> İsterseniz yalnızca tek klasöre kilitlemek için `./start.sh --restricted --workspace /proje/yolunuz` veya farklı port için `--port 39000` kullanabilirsiniz.

### 2. Chrome Eklentisini Yükleyip Token'i Girin
1. Chrome'da `chrome://extensions` adresini açın.
2. **Geliştirici modu (Developer mode)** anahtarını açın.
3. **Paketlenmemiş öğe yükle (Load unpacked)** diyerek `arena-local-bridge/extension` klasörünü seçin.
4. Sağ üstten **Arena Local Bridge** eklenti simgesine tıklayın.
5. Terminalde yazan **API Token** değerini yapıştırıp **Kaydet ve Bağlan** butonuna basın (`Tam Erisim` veya `Bagli` durumunu göreceksiniz).

---

## Desteklenen Araçlar

- **Tek seferlik komut:** `run_command` (opsiyonel `stdin`, `cwd`, `timeout`)
- **Kalıcı / İnteraktif Terminal (PTY/Shell):**
  - `terminal_start` — arka planda gerçek bir etkileşimli terminal oturumu başlatır (`session_id` döner).
  - `terminal_write` — açık terminale komut/metin yazar veya `Ctrl+C` (`ctrl: "c"`) gönderir, yeni çıktıyı döner.
  - `terminal_read` — açık terminaldeki yeni çıktıları okur.
  - `terminal_list` / `terminal_kill` — açık terminalleri listeler / kapatır.
- **Masaüstü Terminal Penceresi:** `open_terminal_window` — işletim sisteminizde gerçek görünür terminal penceresi açar (`wt.exe`/`cmd.exe`, `Terminal.app`, `gnome-terminal`/`konsole`/`xterm` vb.).
- **Dosya Sistemi:** `list_dir`, `read_file`, `write_file`, `edit_file`, `delete_path`.

---

## Klasör Yapısı

```text
arena-local-bridge/
├── start.sh                # Linux/macOS tek komutluk başlatıcı
├── start.bat               # Windows çift tıkla / tek komut başlatıcı
├── server/
│   └── local_server.py     # 127.0.0.1 HTTP sunucusu + token/origin koruması
├── extension/              # Chrome Manifest V3 eklentisi
├── native-host/            # Paylaşılan araç motoru ve PTY oturum yöneticisi
├── install/                # (Opsiyonel eski 2A Native Messaging betikleri)
└── tests/
    ├── test_local_server.py
    ├── test_host.py
    └── test_parser.js
```

---

## Güvenlik Özellikleri

- **Yalnızca `127.0.0.1`:** Sunucu ağ dışına açılmaz.
- **Bearer Token + Origin Kontrolü:** Her istekte `Authorization: Bearer <token>` gerekir; tarayıcıdaki normal web sitelerinden (`http://` / `https://`) gelen doğrudan `Origin` istekleri `403` ile reddedilir.
- **Manuel Onay:** Hiçbir araç **Onayla ve Çalıştır** butonuna basılmadan çalışmaz.
- **Denetim Kaydı:** Tüm işlemler `~/.arena-local-bridge/audit.log` dosyasına kaydedilir.

---

## Testleri Çalıştırma

```bash
python3 -B -m unittest discover -s arena-local-bridge/tests -p "test_*.py" -v
node --test arena-local-bridge/tests/test_parser.js
```
