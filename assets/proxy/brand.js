// Derived from SIPMediaGW deploy/proxyAPI/brand.js (Apache-2.0). Changes: the service name
// and the accent colour (--bf), both taken from the eduMEET client, English when the browser asks
// for none of the languages of the pages, no link to the portal page (nginx does not serve it),
// and "Federation" as the name of the full list of the instances.
// Loaded before either page's own script, which is why these are plain
// globals: nothing here is worth a module for.
const BRAND = {
  name: 'eduMEET',
  tagline: '',
  logo: '/favicon/favicon.svg',                       // e.g. '/pairing/static/logo.svg'; empty hides it

  // The pairing page's footer link: the service's presentation, the portal.
  // The pure documentation stays one step away, in the portal's own footer.
  // Keep per-language URLs if the target route ever becomes locale-sensitive.
  docUrl: '',
  docLabelFr: 'Présentation du service',
  docLabelEn: 'Service overview',

  lang: 'en',
  allPlatforms: 'Federation',
  // The Federation's entries are organisations: the phone says so in every language.
  texts: {
    en: {
      pickPlatform: 'Choose your organisation',
      allPlatformsHost: 'all organisations',
      linkOtherPlatform: (host) => `This link is for ${host}. Choose that organisation first.`,
    },
    fr: {
      pickPlatform: 'Choisissez votre organisation',
      allPlatformsHost: 'toutes les organisations',
      linkOtherPlatform: (host) => `Ce lien est pour ${host}. Choisissez d’abord cette organisation.`,
    },
    cs: {
      pickPlatform: 'Vyberte svou organizaci',
      allPlatformsHost: 'všechny organizace',
      linkOtherPlatform: (host) => `Tento odkaz patří k ${host}. Nejprve vyberte tuto organizaci.`,
    },
    da: {
      pickPlatform: 'Vælg din organisation',
      allPlatformsHost: 'alle organisationer',
      linkOtherPlatform: (host) => `Dette link er til ${host}. Vælg først den organisation.`,
    },
    de: {
      pickPlatform: 'Wählen Sie Ihre Organisation',
      allPlatformsHost: 'alle Organisationen',
      linkOtherPlatform: (host) => `Dieser Link gehört zu ${host}. Wählen Sie zuerst diese Organisation.`,
    },
    el: {
      pickPlatform: 'Επιλέξτε τον οργανισμό σας',
      allPlatformsHost: 'όλοι οι οργανισμοί',
      linkOtherPlatform: (host) => `Αυτός ο σύνδεσμος είναι για το ${host}. Επιλέξτε πρώτα αυτόν τον οργανισμό.`,
    },
    es: {
      pickPlatform: 'Elija su organización',
      allPlatformsHost: 'todas las organizaciones',
      linkOtherPlatform: (host) => `Este enlace es de ${host}. Elija primero esa organización.`,
    },
    hr: {
      pickPlatform: 'Odaberite svoju organizaciju',
      allPlatformsHost: 'sve organizacije',
      linkOtherPlatform: (host) => `Ova poveznica je za ${host}. Najprije odaberite tu organizaciju.`,
    },
    hu: {
      pickPlatform: 'Válassza ki a szervezetét',
      allPlatformsHost: 'minden szervezet',
      linkOtherPlatform: (host) => `Ez a link a(z) ${host} címhez tartozik. Először azt a szervezetet válassza.`,
    },
    it: {
      pickPlatform: 'Scegli la tua organizzazione',
      allPlatformsHost: 'tutte le organizzazioni',
      linkOtherPlatform: (host) => `Questo link è per ${host}. Scegli prima quell’organizzazione.`,
    },
    nb: {
      pickPlatform: 'Velg organisasjonen din',
      allPlatformsHost: 'alle organisasjoner',
      linkOtherPlatform: (host) => `Denne lenken er for ${host}. Velg den organisasjonen først.`,
    },
    pl: {
      pickPlatform: 'Wybierz swoją organizację',
      allPlatformsHost: 'wszystkie organizacje',
      linkOtherPlatform: (host) => `Ten link dotyczy ${host}. Najpierw wybierz tę organizację.`,
    },
    pt: {
      pickPlatform: 'Escolha a sua organização',
      allPlatformsHost: 'todas as organizações',
      linkOtherPlatform: (host) => `Este link é para ${host}. Escolha primeiro essa organização.`,
    },
    ro: {
      pickPlatform: 'Alegeți organizația dumneavoastră',
      allPlatformsHost: 'toate organizațiile',
      linkOtherPlatform: (host) => `Acest link este pentru ${host}. Alegeți mai întâi acea organizație.`,
    },
    ru: {
      pickPlatform: 'Выберите свою организацию',
      allPlatformsHost: 'все организации',
      linkOtherPlatform: (host) => `Эта ссылка для ${host}. Сначала выберите эту организацию.`,
    },
    tr: {
      pickPlatform: 'Kurumunuzu seçin',
      allPlatformsHost: 'tüm kurumlar',
      linkOtherPlatform: (host) => `Bu bağlantı ${host} için. Önce o kurumu seçin.`,
    },
    uk: {
      pickPlatform: 'Виберіть свою організацію',
      allPlatformsHost: 'усі організації',
      linkOtherPlatform: (host) => `Це посилання для ${host}. Спершу виберіть цю організацію.`,
    },
  },
};

document.title = BRAND.name;
const iconLink = document.querySelector('link[rel="icon"]');
if (iconLink) {
  iconLink.href = BRAND.logo || '';
}
// The portal loads this file too, for BRAND.name alone: guard the elements
// it does not have.
const brandName = document.querySelector('#brand-name');
if (brandName) brandName.textContent = BRAND.name;
const brandTagline = document.querySelector('#brand-tagline');
if (brandTagline) brandTagline.textContent = BRAND.tagline;
if (BRAND.logo) {
  const logo = document.getElementById('brand-logo');
  if (logo) {
    logo.src = BRAND.logo;
    logo.alt = BRAND.name;
  }
}

// The client's Material UI primary colour, light and dark.
const brandStyle = document.createElement('style');
brandStyle.textContent = ':root { --bf: #1976d2; } [data-theme="dark"] { --bf: #90caf9; }';
document.head.appendChild(brandStyle);
