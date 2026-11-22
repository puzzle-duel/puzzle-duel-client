# STAGING TURNAVA HAMLE GECİKMESİ — GÖZLEMLENEBİLİRLİK SÖZLEŞMESİ

## PROBLEM
Pratik modda hamle akıcı; staging turnuva modunda kullanıcı hamleyi dokunduktan **1–2 saniye** sonra ekranda görüyor. **Mekanik / animasyon / turnuva kuralları değiştirilmeyecek.** Önce ölç, sonra ilgili katmanda düzelt.

## CLIENT — BİR HAMLE = BİR TRACE
Her kabul edilen turnuva tap'i güvenli 128-bit hex `traceId` üretir. `Stopwatch` monoton saatinden alınan `durationMs` değerleri tap anından itibaren **kümülatiftir**; frame-render zamanı değildir.

| operation | ölçüm anı |
| --- | --- |
| `move_tap_accepted` | guard kontrolleri geçilip işlem alındığı an |
| `move_writer_checked` | canlı writer oturumu doğrulandı / yenileme denendi |
| `move_command_returned` | POST commands `Future` tamamlandı |
| `move_board_reloaded` | GET board + yanıt değerlendirmesi tamamlandı |
| `move_animation_arming` | authoritative resolution uygulamasından hemen önce |
| `move_resolution_applied` | authoritative resolution uygulamasından hemen sonra |
| `move_pipeline_returned` | komut işlem bloğu bitti (animasyonun bitmesi DEĞİL) |

Staging'de `UatApi` POST command ve GET board HTTP complete olayları, aynı `traceId` ile iki farklı `requestId` içerir. Bunların `durationMs` değerleri **her ayrı HTTP request'in client toplam süresidir**. Backend Oracle `http-diagnostics.log` aynı `requestId` için backend `durationMs` ölçer.

Denklem (her HTTP request için): **client_ms − server_ms = client network + connection + transport/body decode + diğer client HTTP overhead**. Bu fark Flutter rendering süresi değildir; sıfırdan biraz küçük fark saat/ölçüm sınırlarıyla mümkündür.

Bir hamlenin görünen beklemesi: `move_animation_arming` ≈ writer session wait + command HTTP + board HTTP + aradaki client işlem süreleri. Eşleştirme için oyuncu ID, token, board, seri ID, idempotency key, koordinat veya ham payload toplamayın.

## LOG GÖNDER
Staging build'de Ayarlar > **Log Gönder (UAT)** zorunludur. Ring buffer: 300 olay / 256KiB / 2 saat, process-local. Gönderim: son **64** uygun olay (backend max64); terminale bağlanma şartı yok. **Uygulama öldüyse veya yeni process başladıysa önceki process'in RAM event'leri artık mevcut değildir.** Açıkça eksik rapor uyarısı verilmeli; geçmişe dönük süre uydurulmamalı.

Önceden oynanmış bir oturumun, instrumentation eklenmeden önceki olayları geri kazanılamaz. Bu telemetri ancak yeni build ile yapılan hamlelerde veri üretir.

## SERVER / ACTION
Backend draft PR #48: `PZD Staging Move Latency (read-only)`, `report_id` (UUID) alır. Oracle'da tutulan journal event'i ve HTTP metadata eşleştirmesi Oracle içinde yapılır. Public GitHub output: yalnız `n/p50/p95/max` yuvarlanmış süre ve aşama istatistikleri. Ham log, traceId, requestId, playerId, token ve payload gösterilmez.

Journald erişilemezse veya log retention dolduysa `REPORT_NOT_AVAILABLE` sonucu, gerçek bir gecikme ölçümü **DEĞİLDİR**. Workflow gerçek staging ortamında doğrulanmadan gate PASS sayılmaz.

## ACCEPTANCE GATE
1. Staging iOS ve Android: Log Gönder + Crash Test görünür; Log Gönder 201/reportId.
2. Tek bir hareketin en az `move_tap_accepted`, `move_command_returned`, `move_board_reloaded`, `move_animation_arming` fazları aynı trace altında bulunur.
3. POST commands ve GET board her biri farklı requestId fakat aynı traceId taşır.
4. Aynı requestId Oracle backend kaydında eşleşir; delta raporlanır.
5. Kayıp yanıt / 401 / 409 / timeout: hamle sonuçları ve retry mantığı aynı kalır, loglar exception/secret içermez.
6. Flutter analyze, ilgili testler ve staging cihaz UAT PASS olmadan merge/deploy yok.
7. Production derlemede staging move fazları / manuel diagnostic butonları devre dışı.
