const mangayomiSources = [{
  "name": "JKAnime",
  "lang": "es",
  "baseUrl": "https://jkanime.net",
  "apiUrl": "",
  "iconUrl": "https://jkanime.net/favicon.ico",
  "typeSource": "single",
  "itemType": 1,
  "isNsfw": false,
  "version": "0.0.1",
  "dateFormat": "",
  "dateFormatLocale": "",
  "pkgPath": "anime/src/es/jkanime.js"
}];

class DefaultExtension extends MProvider {
  constructor() {
    super();
    this.client = new Client();
  }

  get headers() {
    return {
      "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36",
      "Referer": this.source.baseUrl + "/",
    };
  }

  async get(url) {
    if (!url.startsWith("http")) url = this.source.baseUrl + url;
    const res = await this.client.get(url, this.headers);
    if (res.statusCode !== 200) {
      throw new Error("HTTP " + res.statusCode + " en " + url);
    }
    return res.body;
  }

  // ---------- LISTAS ----------
  parseList(html) {
    const doc = new Document(html);
    const list = [];
    const selectors = [".anime__item", ".card", ".anime_item", "div.col-lg-2"];
    let items = [];
    for (const s of selectors) {
      items = doc.select(s);
      if (items.length > 0) break;
    }
    if (items.length === 0) {
      throw new Error("Selectores de lista no coinciden. Inicio del HTML: " + html.substring(0, 300));
    }
    for (const el of items) {
      const a = el.selectFirst("a");
      if (!a) continue;
      const link = a.getHref;
      const img = el.selectFirst("img");
      const bg = el.selectFirst("[data-setbg]");
      const name = (el.selectFirst("h5 a, h5, h3, .title") || a).text.trim();
      const imageUrl = bg
        ? bg.attr("data-setbg")
        : img
        ? (img.attr("data-src") || img.attr("src"))
        : "";
      if (name && link) list.push({ name, link, imageUrl });
    }
    return { list, hasNextPage: list.length > 0 };
  }

  async getPopular(page) {
    return this.parseList(await this.get("/directorio/?p=" + page));
  }

  async getLatestUpdates(page) {
    return this.parseList(await this.get("/directorio/?p=" + page + "&estado=emision"));
  }

  async search(query, page, filters) {
    return this.parseList(
      await this.get("/buscar/" + encodeURIComponent(query) + "/" + page + "/")
    );
  }

  // ---------- DETALLE ----------
  async getDetail(url) {
    const html = await this.get(url);
    const doc = new Document(html);
    const base = url.startsWith("http") ? url : this.source.baseUrl + url;
    const slug = base.replace(/\/$/, "");

    const name = (doc.selectFirst("h3, h1") || { text: "" }).text.trim();
    const bg = doc.selectFirst("[data-setbg]");
    const imageUrl = bg ? bg.attr("data-setbg") : "";
    const descEl = doc.selectFirst("p.scroll, .sinopsis, .anime__details__text p");
    const description = descEl ? descEl.text.trim() : "";
    const genre = doc.select("a[href*='/genero/']").map((g) => g.text.trim());
    const status = /en emisi/i.test(html) ? 0 : /concluido|finalizado/i.test(html) ? 1 : 5;

    let total = 0;
    for (const m of html.matchAll(/jkanime\.net\/[^\/"']+\/(\d+)\/?/g)) {
      total = Math.max(total, parseInt(m[1]));
    }
    if (total === 0) {
      const t = html.match(/Episodios:?\s*<[^>]*>\s*(\d+)/i);
      if (t) total = parseInt(t[1]);
    }
    if (total === 0) total = 1;

    const episodes = [];
    for (let i = total; i >= 1; i--) {
      episodes.push({ name: "Episodio " + i, url: slug + "/" + i + "/" });
    }

    return { name, imageUrl, description, status, genre, episodes };
  }

  // ---------- VIDEO ----------
  b64decode(str) {
    const chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    str = str.replace(/[^A-Za-z0-9+/]/g, "");
    let out = "", buf = 0, bits = 0;
    for (const c of str) {
      buf = (buf << 6) | chars.indexOf(c);
      bits += 6;
      if (bits >= 8) {
        bits -= 8;
        out += String.fromCharCode((buf >> bits) & 0xff);
      }
    }
    return out;
  }

  async getVideoList(url) {
    const html = await this.get(url);
    const videos = [];

    const found = [];
    for (const m of html.matchAll(/"remote"\s*:\s*"([A-Za-z0-9+\/=]+)"/g)) {
      found.push(this.b64decode(m[1]));
    }
    for (const m of html.matchAll(/<iframe[^>]+src="([^"]+)"/g)) {
      found.push(m[1]);
    }
    if (found.length === 0) {
      throw new Error("No encontré servidores en " + url + ". Revisa 'servers' en el HTML.");
    }

    for (const embed of found) {
      try {
        const page = await this.client.get(embed, {
          ...this.headers,
          Referer: this.source.baseUrl + "/",
        });
        const m3u8 = page.body.match(/https?:[^"'\s\\]+\.m3u8[^"'\s\\]*/);
        const mp4 = page.body.match(/https?:[^"'\s\\]+\.mp4[^"'\s\\]*/);
        const host = embed.split("/")[2];
        if (m3u8) {
          videos.push({ url: m3u8[0], originalUrl: m3u8[0], quality: host + " (HLS)", headers: { Referer: embed } });
        } else if (mp4) {
          videos.push({ url: mp4[0], originalUrl: mp4[0], quality: host + " (MP4)", headers: { Referer: embed } });
        }
      } catch (e) {}
    }
    return videos;
  }

  getFilterList() { return []; }
  getSourcePreferences() { return []; }
}
