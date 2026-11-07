import 'package:mangayomi/bridge_lib.dart';

class JKAnime extends MProvider {
  JKAnime({required this.source});

  MSource source;

  final Client client = Client();

  Map<String, String> get headers => {
        "User-Agent":
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36",
        "Referer": "${source.baseUrl}/",
      };

  Future<String> getHtml(String url) async {
    if (!url.startsWith("http")) {
      url = "${source.baseUrl}$url";
    }
    final res = await client.get(Uri.parse(url), headers: headers);
    return res.body;
  }

  MPages parseList(String html) {
    final document = parseHtml(html);
    List<MManga> list = [];
    var items = document.select(".anime__item");
    if (items.isEmpty) {
      items = document.select(".card");
    }
    if (items.isEmpty) {
      final n = html.length > 300 ? 300 : html.length;
      throw "Selectores de lista no coinciden. HTML: ${html.substring(0, n)}";
    }
    for (var el in items) {
      final a = el.selectFirst("a");
      if (a == null) continue;
      MManga anime = MManga();
      final nameEl = el.selectFirst("h5 a, h5, h3, .title");
      anime.name = (nameEl != null ? nameEl.text : a.text).trim();
      anime.link = a.getHref;
      final bg = el.selectFirst("[data-setbg]");
      final img = el.selectFirst("img");
      if (bg != null) {
        anime.imageUrl = bg.attr("data-setbg");
      } else if (img != null) {
        final lazy = img.attr("data-src");
        anime.imageUrl = (lazy != null && lazy.isNotEmpty) ? lazy : img.attr("src");
      }
      if (anime.name.isNotEmpty && anime.link.isNotEmpty) {
        list.add(anime);
      }
    }
    return MPages(list, list.isNotEmpty);
  }

  @override
  Future<MPages> getPopular(int page) async {
    final res = await client.get(
        Uri.parse("${source.baseUrl}/directorio/?p=$page"),
        headers: headers);
    final body = res.body;
    print("STATUS: ${res.statusCode}");
    print("LARGO: ${body.length}");
    print(body.substring(0, body.length > 600 ? 600 : body.length));
    return parseList(body);
  }

  @override
  Future<MPages> getLatestUpdates(int page) async {
    final html = await getHtml("/directorio/?p=$page&estado=emision");
    return parseList(html);
  }

  @override
  Future<MPages> search(String query, int page, FilterList filterList) async {
    final q = query.replaceAll(" ", "_");
    final html = await getHtml("/buscar/$q/$page/");
    return parseList(html);
  }

  @override
  Future<MManga> getDetail(String url) async {
    final html = await getHtml(url);
    final document = parseHtml(html);
    MManga anime = MManga();

    final nameEl = document.selectFirst("h3, h1");
    if (nameEl != null) anime.name = nameEl.text.trim();

    final bg = document.selectFirst("[data-setbg]");
    if (bg != null) anime.imageUrl = bg.attr("data-setbg");

    final desc = document.selectFirst("p.scroll, .sinopsis, .anime__details__text p");
    if (desc != null) anime.description = desc.text.trim();

    List<String> genres = [];
    for (var g in document.select("a[href*='/genero/']")) {
      genres.add(g.text.trim());
    }
    anime.genre = genres;

    final lower = html.toLowerCase();
    if (lower.contains("en emisi")) {
      anime.status = MStatus.ongoing;
    } else if (lower.contains("concluido") || lower.contains("finalizado")) {
      anime.status = MStatus.completed;
    } else {
      anime.status = MStatus.unknown;
    }

    String base = url.startsWith("http") ? url : "${source.baseUrl}$url";
    while (base.endsWith("/")) {
      base = base.substring(0, base.length - 1);
    }

    int total = 0;
    final reg = RegExp(r'jkanime\.net/[^/"' + "'" + r']+/(\d+)/?');
    for (var m in reg.allMatches(html)) {
      final n = int.parse(m.group(1)!);
      if (n > total) total = n;
    }
    if (total == 0) {
      final t = RegExp(r'Episodios:?\s*<[^>]*>\s*(\d+)', caseSensitive: false)
          .firstMatch(html);
      if (t != null) total = int.parse(t.group(1)!);
    }
    if (total == 0) total = 1;

    List<MChapter> episodes = [];
    for (int i = total; i >= 1; i--) {
      MChapter ep = MChapter();
      ep.name = "Episodio $i";
      ep.url = "$base/$i/";
      episodes.add(ep);
    }
    anime.chapters = episodes;
    return anime;
  }

  String b64decode(String input) {
    const chars =
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    final clean = input.replaceAll(RegExp(r'[^A-Za-z0-9+/]'), "");
    String out = "";
    int buf = 0;
    int bits = 0;
    for (int i = 0; i < clean.length; i++) {
      buf = (buf << 6) | chars.indexOf(clean[i]);
      bits += 6;
      if (bits >= 8) {
        bits -= 8;
        out += String.fromCharCode((buf >> bits) & 0xff);
        buf = buf & ((1 << bits) - 1);
      }
    }
    return out;
  }

  @override
  Future<List<MVideo>> getVideoList(String url) async {
    final html = await getHtml(url);
    List<MVideo> videos = [];
    List<String> found = [];

    for (var m in RegExp(r'"remote"\s*:\s*"([A-Za-z0-9+/=]+)"').allMatches(html)) {
      found.add(b64decode(m.group(1)!));
    }
    for (var m in RegExp(r'<iframe[^>]+src="([^"]+)"').allMatches(html)) {
      found.add(m.group(1)!);
    }

    for (var embed in found) {
      try {
        final res = await client.get(Uri.parse(embed), headers: {
          "User-Agent": headers["User-Agent"]!,
          "Referer": "${source.baseUrl}/",
        });
        final body = res.body;
        final host = embed.split("/").length > 2 ? embed.split("/")[2] : embed;
        final m3u8 = RegExp(r'https?:[^"\s\\]+\.m3u8[^"\s\\]*').firstMatch(body);
        final mp4 = RegExp(r'https?:[^"\s\\]+\.mp4[^"\s\\]*').firstMatch(body);
        if (m3u8 != null) {
          MVideo v = MVideo();
          v.url = m3u8.group(0)!;
          v.originalUrl = m3u8.group(0)!;
          v.quality = "$host (HLS)";
          v.headers = {"Referer": embed};
          videos.add(v);
        } else if (mp4 != null) {
          MVideo v = MVideo();
          v.url = mp4.group(0)!;
          v.originalUrl = mp4.group(0)!;
          v.quality = "$host (MP4)";
          v.headers = {"Referer": embed};
          videos.add(v);
        }
      } catch (e) {}
    }
    return videos;
  }

  @override
  List<dynamic> getFilterList() {
    return [];
  }

  @override
  List<dynamic> getSourcePreferences() {
    return [];
  }
}

JKAnime main(MSource source) {
  return JKAnime(source: source);
}
