# Arena.ai Local Terminal & Tool Bridge (Seçenek 2A — Chrome Native Messaging)

Arena.ai sohbet penceresinde modelin ürettiği araç ve terminal çağrılarını (`arena-tool` bloklarını), **manuel onayınızla** bilgisayarınızda çalıştıran Chrome Manifest V3 eklentisi ve yerel Native Messaging köprüsüdür.

Açık genel ağ portu bırakmaz; Chrome'un yerel `stdin/stdout` **Native Messaging** protokolünü kullanır. Kalıcı interaktif terminal oturumları için arka planda yalnızca `127.0.0.1` üzerinde token doğrulamalı yerel `terminal_daemon.py` çalışır.

---

## Klasör Yapısı

```text
arena-local-bridge/
├── extension/              # Chrome Manifest V3 eklentisi
│   ├── manifest.json
│   ├── background.js       # Native Messaging servis işçisi
│   ├── content.js          # Arena.ai DOM izleyicisi ve onay kartları
│   ├── content.css
│   ├── tool-parser.js      # arena-tool ayrıştırıcı + sistem promptu
│   ├── popup.html / .js / .css
│   └── icons/
├── native-host/
│   ├── host.py             # Saf Python 3 Native Messaging sunucusu
│   └── terminal_daemon.py  # Kalıcı PTY / interaktif terminal yöneticisi
├── install/
│   ├── install.py          # Windows / macOS / Linux kurulum betiği
│   ├── uninstall.py
│   └── com.arena.local_bridge.template.json
└── tests/
    ├── test_host.py        # Uçtan uca Native Host + terminal + güvenlik testleri
    └── test_parser.js      # JS parser birim testleri
```

---

## Desteklenen Araçlar

- **Tek seferlik komut:** `run_command` (opsiyonel `stdin`, `cwd`, `timeout`)
- **Kalıcı / İnteraktif Terminal (PTY/Shell):**
  - `terminal_start` — arka planda gerçek bir etkileşimli terminal oturumu başlatır (`session_id` döner).
  - `terminal_write` — açık terminale komut/metin yazar veya `Ctrl+C` (`ctrl: "c"`) gönderir, yeni çıktıyı döner.
  - `terminal_read` — açık terminalden yeni çıktıları okur.
  - `terminal_list` / `terminal_kill` — açık terminalleri listeler / kapatır.
- **Masaüstü Terminal Penceresi:** `open_terminal_window` — işletim sisteminizde gerçek bir görünür terminal penceresi açar (`wt.exe`/`cmd.exe`, `Terminal.app`, `gnome-terminal`/`konsole`/`xterm` vb.).
- **Dosya Sistemi:** `list_dir`, `read_file`, `write_file`, `edit_file`, `delete_path`.

---

## Kurulum Adımları

### 1. Chrome Eklentisini Yükleyin
1. Chrome'da `chrome://extensions` adresini açın.
2. Sağ üstten **Geliştirici modu (Developer mode)** anahtarını açın.
3. **Paketlenmemiş öğe yükle (Load unpacked)** butonuna basın ve `arena-local-bridge/extension` klasörünü seçin.
4. Eklentinin **ID** değerini kopyalayın.

### 2. Native Messaging Host'u Kaydedin

**Tüm bilgisayara erişim (Tam Erişim modu):**
```bash
python3 install/install.py \
  --extension-id <32_KARAKTERLIK_EKLENTI_ID> \
  --full-access
```

**Yalnızca belirli bir klasöre kısıtlı mod (Workspace Jail):**
```bash
python3 install/install.py \
  --extension-id <32_KARAKTERLIK_EKLENTI_ID> \
  --restricted \
  --workspace /proje/yolunuz
```

> Windows'ta `python` veya `py -3` kullanabilirsiniz. Kurulum betiği Windows için `host_wrapper.bat` + Registry kaydını, Linux/macOS için `NativeMessagingHosts/com.arena.local_bridge.json` dosyasını otomatik oluşturur.

### 3. Bağlantıyı Test Edin
1. Chrome araç çubuğundan **Arena Local Bridge** simgesine tıklayın.
2. **Bağlantıyı Test Et (Ping)** ile erişim modunu (`Tam Erisim` veya `Bagli`) doğrulayın.

---

## Güvenlik Notları

- **Her çağrıda manuel onay:** Hiçbir komut veya dosya işlemi **Onayla ve Çalıştır** butonuna basılmadan çalışmaz.
- **Tam Erişim vs Klasör Kilidi:** `~/.arena-local-bridge/config.json` içindeki `full_system_access` (`true`/`false`) ve `allowed_tools` alanlarıyla yetkileri dilediğiniz zaman düzenleyebilirsiniz.
- **Denetim Kaydı:** Tüm çalıştırılan işlemler `~/.arena-local-bridge/audit.log` dosyasına kaydedilir.

---

## Testleri Çalıştırma

```bash
python3 -m unittest discover -s arena-local-bridge/tests -p "test_*.py" -v
node --test arena-local-bridge/tests/test_parser.js
```
