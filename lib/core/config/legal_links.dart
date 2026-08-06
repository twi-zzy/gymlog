/// Legal & support links — single source for store-review-visible URLs.
library;

const kPrivacyPolicyUrl =
    'https://atharvoid.github.io/Gym-Log/legal/privacy-policy.html';
const kTermsOfServiceUrl =
    'https://atharvoid.github.io/Gym-Log/legal/terms-of-service.html';
const kAccountDeletionUrl =
    'https://atharvoid.github.io/Gym-Log/legal/delete-account.html';

/// Where problem reports and support live: the GymLog Telegram channel.
///
/// A t.me link CANNOT carry a prefilled message body, so "Report a problem"
/// posts its diagnostic template through the `report-problem` Supabase Edge
/// Function — which holds the Telegram bot token server-side — and falls
/// back to clipboard + this link when the relay is unreachable. There is
/// deliberately no support email in the app anymore (ship-readiness #5).
const kTelegramChannelUrl = 'https://t.me/gym_log';

const kExerciseCatalogVersion = 2;
