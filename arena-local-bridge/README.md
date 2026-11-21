# Arena.ai Local Terminal & Tool Bridge (Seçenek 2A — Chrome Native Messaging)

Arena.ai sohbet penceresinde modelin ürettiği araç ve terminal çağrılarını (`arena-tool` bloklarını), **manuel onayınızla** kendi bilgisayarınızdaki izinli proje klasörü içinde çalıştıran Chrome Manifest V3 eklentisi ve yerel Native Messaging köprüsüdür.

Açık HTTP/WebSocket portu bırakmaz; Chrome'un yerel `stdin/stdout` **Native Messaging** protokolünü kullanır.

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
│   └── host.py             # Saf Python 3 Native Messaging sunucusu (bağımlılıksız)
├── install/
│   ├── install.py          # Windows / macOS / Linux kurulum betiği
│   ├── uninstall.py
│   └── com.arena.local_bridge.template.json
└── tests/
    ├── test_host.py        # Uçtan uca Native Host + güvenlik testleri
    └── test_parser.js      # JS parser birim testleri
```

---

## Kurulum Adımları

### 1. Chrome Eklentisini Yükleyin
1. Chrome'da `chrome://extensions` adresini açın.
2. Sağ üstten **Geliştirici modu (Developer mode)** anahtarını açın.
3. **Paketlenmemiş öğe yükle (Load unpacked)** butonuna basın ve `arena-local-bridge/extension` klasörünü seçin.
4. Yüklenen eklentinin **ID** değerini kopyalayın (veya eklenti simgesine tıklayıp popup içindeki **Kopyala** butonunu kullanın).

### 2. Native Messaging Host'u Kaydedin
Terminali açıp `arena-local-bridge` klasöründe şu komutu çalıştırın:

```bash
python3 install/install.py \
  --extension-id <32_KARAKTERLIK_EKLENTI_ID> \
  --workspace /calismak/istediginiz/proje/klasoru
```

> Windows'ta `python` veya `py -3` kullanabilirsiniz. Kurulum betiği Windows için `host_wrapper.bat` + Registry kaydını, Linux/macOS için `NativeMessagingHosts/com.arena.local_bridge.json` dosyasını otomatik oluşturur.

### 3. Bağlantıyı Test Edin
1. Chrome araç çubuğundan **Arena Local Bridge** simgesine tıklayın.
2. **Bağlantıyı Test Et (Ping)** ile `Bağlı` durumunu ve aktif `Workspace` yolunu doğrulayın.

---

## Arena.ai Üzerinde Kullanım

1. `https://arena.ai` sohbet sayfasını açın (sağ altta **Local Bridge Bağlı** paneli görünür).
2. Paneldeki **Sistem Promptu Kopyala** veya **Sohbete Yapıştır** butonunu kullanarak sohbetin başında modele araç formatını bildirin.
3. Model aşağıdaki gibi bir blok ürettiğinde, altında otomatik olarak **Onayla ve Çalıştır / Reddet** kartı çıkar:

````markdown
```arena-tool
{
  "id": "call_1",
  "tool": "run_command",
  "args": {
    "command": "git status",
    "cwd": "."
  }
}
```
````

4. **Onayla ve Çalıştır** dediğinizde komut bilgisayarınızdaki `workspace_root` içinde çalışır.
5. Çıktıyı inceledikten sonra **Sohbete Ekle** butonuna basarak sonucu `arena-tool-result` bloğu olarak sohbet kutusuna yerleştirebilir ve gönderebilirsiniz.

---

## Güvenlik Özellikleri

- **Sıfır Otomatik Çalıştırma:** Hiçbir araç kullanıcı onayı olmadan çalışmaz.
- **Workspace Jail:** Tüm dosya okuma/yazma ve komut `cwd` yolları `os.path.realpath` + `os.path.commonpath` ile kontrol edilir; `../` veya sembolik bağ ile `workspace_root` dışına çıkılamaz.
- **Zaman Aşımı & Süreç Grubu Temizliği:** `run_command` zaman aşımına uğrarsa alt süreçlerle birlikte sonlandırılır (`default_timeout_sec: 30`, maks `300`).
- **Denetim Kaydı:** Çalıştırılan tüm araçlar `~/.arena-local-bridge/audit.log` dosyasına kaydedilir.
- **Konfigürasyon Kilidi:** `~/.arena-local-bridge/config.json` içinden `allowed_tools` listesini kısıtlayabilir (ör. `write_file` veya `run_command`'ı kapatabilirsiniz).

---

## Testleri Çalıştırma

```bash
python3 -m unittest discover -s arena-local-bridge/tests -p "test_*.py" -v
node --test arena-local-bridge/tests/test_parser.js
```
