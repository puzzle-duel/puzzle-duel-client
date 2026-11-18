import 'package:material_ui/material_ui.dart';

/// English and Turkish copy for the tournament UAT.
///
/// Material's built-in delegate in this app is English-only, so tournament
/// strings follow [TournamentLocale] rather than replacing that delegate.
final class TournamentLocale extends InheritedWidget {
  const TournamentLocale({super.key, required this.locale, required super.child});

  final Locale locale;

  static Locale of(BuildContext context) {
    final inherited = context.dependOnInheritedWidgetOfExactType<TournamentLocale>();
    return inherited?.locale ?? const Locale('en');
  }

  @override
  bool updateShouldNotify(TournamentLocale oldWidget) => oldWidget.locale != locale;
}

final class TournamentCopy {
  const TournamentCopy(this.locale);

  final Locale locale;

  bool get isTurkish => locale.languageCode == 'tr';

  String pick(String english, String turkish) => isTurkish ? turkish : english;

  static TournamentCopy of(BuildContext context) {
    return TournamentCopy(TournamentLocale.of(context));
  }

  String get appTitle => 'Puzzle Duel';
  String get tagline => pick('Match shapes. Clear lines.', 'Şekilleri eşleştir. Satırları temizle.');
  String get dailyChallenge => pick('Daily challenge', 'Günlük mücadele');
  String get sixGames => pick('Six games', 'Altı oyun');
  String get playToday => pick("Play today's challenge", 'Bugünün mücadelesini oyna');
  String get resume => pick('Resume tournament', 'Turnuvaya devam et');
  String get continueNext => pick('Continue', 'Devam');
  String get viewResults => pick('View results', 'Sonuçları gör');
  String get returnHome => pick('Return home', 'Ana sayfaya dön');
  String get seeGames => pick("Today's games", 'Bugünün oyunları');
  String get dailyBoard => pick('Daily leaderboard', 'Günlük sıralama');
  String get weeklyBoard => pick('Weekly leaderboard', 'Haftalık sıralama');
  String get readyBody => pick(
    'One daily entry. Six games. The server scores every move.',
    'Günde bir giriş. Altı oyun. Her hamleyi sunucu puanlar.',
  );
  String get alreadyClaimed => pick(
    'Today is already claimed. This is the same series.',
    'Bugün zaten alındı. Aynı seri devam ediyor.',
  );
  String get completedBody => pick(
    'Today’s tournament is complete.',
    'Bugünün turnuvası tamam.',
  );
  String get verifiedScore => pick('Verified score', 'Doğrulanmış puan');
  String get currentScore => pick('Current score', 'Güncel puan');
  String get scoreUnavailable => pick('Score not published yet', 'Puan henüz yayımlanmadı');
  String get onTime => pick('On-Time', 'Zamanında');
  String get onTimeMissing => pick('On-Time not awarded', 'Zamanında rozeti yok');
  String get overviewTitle => pick("Today's six games", 'Bugünün altı oyunu');
  String get overviewBody => pick(
    'E1, E2 and E3 are Easy. M1 and M2 are Medium. H1 is Hard. Each board comes from the server.',
    'E1, E2 ve E3 Kolay. M1 ve M2 Orta. H1 Zor. Her tahta sunucudan gelir.',
  );
  String get back => pick('Back', 'Geri');
  String get leaveTitle => pick('Leave this game?', 'Bu oyundan çıkılsın mı?');
  String get leaveBody => pick(
    'Today’s series stays on the server. You can resume it from Home. Leaving does not add time.',
    'Bugünün serisi sunucuda durur. Ana sayfadan devam edebilirsin. Çıkmak süre eklemez.',
  );
  String get stay => pick('Keep playing', 'Oynamaya devam');
  String get leave => pick('Go to Home', 'Ana sayfaya git');
  String get selectPiece => pick('Selected', 'Seçili');
  String get sending => pick('Sending this move…', 'Bu hamle gönderiliyor…');
  String get unknownCommand => pick(
    'The outcome is unknown. Retry only this move.',
    'Sonuç bilinmiyor. Yalnızca bu hamleyi yeniden dene.',
  );
  String get retrySame => pick('Retry the same move', 'Aynı hamleyi yeniden dene');
  String get idle => pick('Idle', 'Boşta');
  String get gameScore => pick('Game score', 'Oyun puanı');
  String get totalScore => pick('Total', 'Toplam');
  String get nextGame => pick('Next', 'Sonraki');
  String get finishedTitle => pick('Game complete', 'Oyun bitti');
  String get moveLimitEnded => pick('The move limit ended this game.', 'Hamle hakkı bitince oyun kapandı.');
  String get noMovesEnded => pick('No legal placement remains.', 'Yerleştirilecek yasal hamle kalmadı.');
  String get gameFinished => pick('The server closed this game.', 'Sunucu bu oyunu kapattı.');
  String get resultsTitle => pick('Tournament complete', 'Turnuva tamam');
  String get resultsPending => pick(
    'The verified result is not available yet.',
    'Doğrulanmış sonuç henüz yok.',
  );
  String get easy => pick('Easy', 'Kolay');
  String get medium => pick('Medium', 'Orta');
  String get hard => pick('Hard', 'Zor');
  String get all => pick('All', 'Tümü');
  String get you => pick('You', 'Sen');
  String get emptyBoard => pick('No verified scores on this board yet.', 'Bu tabloda henüz doğrulanmış puan yok.');
  String get notOnPage => pick('Your rank is not on this page.', 'Sıralaman bu sayfada değil.');
  String get provisional => pick('Provisional', 'Geçici');
  String get finalLabel => pick('Final', 'Kesin');
  String get tryAgain => pick('Try again', 'Yeniden dene');
  String get loading => pick('Loading the tournament…', 'Turnuva yükleniyor…');
  String get reference => pick('Reference', 'Referans');
  String get unauthorized => 'Unauthorized. Issue a new UAT bearer and relaunch.';
  String get timedOut => pick('The server timed out.', 'Sunucu zaman aşımına uğradı.');
  String get offline => pick('Offline. Nothing was confirmed.', 'Çevrimdışı. Hiçbir şey onaylanmadı.');
  String get writerBlocked => pick(
    'This device is not the active writer. Continue on the device that claimed today.',
    'Bu cihaz yazıcı değil. Bugünü alan cihazda devam et.',
  );
  String get staleBoard => pick(
    'The board changed. Showing the server position.',
    'Tahta değişti. Sunucudaki konum gösteriliyor.',
  );
  String get couldNotRead => pick('The server could not read that request.', 'Sunucu bu isteği okuyamadı.');
  String get rateLimited => pick('Too many requests. Wait and retry the same move.', 'Çok fazla istek. Bekle ve aynı hamleyi dene.');
  String get windowClosed => pick('Today’s claim window is closed.', 'Bugünün kayıt penceresi kapalı.');
  String get rejectedMove => pick('The server did not accept that move.', 'Sunucu bu hamleyi kabul etmedi.');
  String get genericFailure => pick('Something went wrong.', 'Bir şeyler ters gitti.');
  String get boardUnreadable => pick('The server board could not be shown.', 'Sunucu tahtası gösterilemedi.');

  String objective(int moves, int size) => pick(
    'Select a piece, then tap a highlighted empty tile. $moves moves left on a $size×$size board.',
    'Bir parça seç, sonra vurgulanan boş kareye dokun. $size×$size tahtada $moves hamle kaldı.',
  );

  String movesLeft(int moves) => pick('$moves left', '$moves kaldı');

  String rankLabel(Object? rank) => pick('Rank $rank', 'Sıra $rank');

  String difficultyOf(String? label) {
    if (label == null || label.isEmpty) return '';
    if (label.startsWith('E')) return easy;
    if (label.startsWith('M')) return medium;
    if (label.startsWith('H')) return hard;
    return label;
  }

  String finishReason(String? reason) {
    return switch (reason) {
      'move_limit_reached' => moveLimitEnded,
      'no_legal_moves' => noMovesEnded,
      _ => gameFinished,
    };
  }

  String forError(String? code) {
    return switch (code) {
      'TIMEOUT' => timedOut,
      'OFFLINE' => offline,
      'UNAUTHENTICATED' => unauthorized,
      'WRITER_NOT_AUTHORIZED' => writerBlocked,
      'STATE_CONFLICT' => staleBoard,
      'MALFORMED_REQUEST' => couldNotRead,
      'RATE_LIMITED' => rateLimited,
      'CLAIM_WINDOW_CLOSED' => windowClosed,
      'outcome_unknown' => unknownCommand,
      'BOARD_UNREADABLE' => boardUnreadable,
      null || '' => genericFailure,
      _ => rejectedMove,
    };
  }

  String categoryLabel(String category) {
    return switch (category) {
      'EASY' => easy,
      'MEDIUM' => medium,
      'HARD' => hard,
      'ALL' => all,
      _ => category,
    };
  }
}

final class TournamentCopyDelegate extends LocalizationsDelegate<TournamentCopy> {
  const TournamentCopyDelegate();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<TournamentCopy> load(Locale locale) async => TournamentCopy(locale);

  @override
  bool shouldReload(covariant TournamentCopyDelegate old) => false;
}
