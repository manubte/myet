// JKAnime Dart | v6 | v5 + prints de progreso en getPopular (ver Console)
import 'dart:convert';
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
    if (res.statusCode != 200) {
      throw "HTTP ${res.statusCode} en $url";
    }
    return res.body;
  }

  String describe(String html) {
    String title = "";
    final t = RegExp(r'<title[^>]*>([^<]*)</title>', caseSensitive: false)
        .firstMatch(html);
    if (t != null) title = t.group(1)!.trim();
    return "TITULO: $title | LARGO: ${html.length}";
  }

  // ---------- LISTAS ----------
  // JKAnime mete la lista como JSON dentro del HTML: [{"id":..,"title":..,"image":..,"slug":..,"url":..}, ...]
  List<MManga> parseEmbedded(String html) {
    List<MManga> list = [];
    int from = 0;
    while (list.isEmpty) {
      final start = html.indexOf('[{"id":', from);
      if (start < 0) break;
      from = start + 1;

      int depth = 0;
      bool inStr = false;
      bool esc = false;
      int end = -1;
      for (int i = start; i < html.length; i++) {
        final c = html[i];
        if (inStr) {
          if (esc) {
            esc = false;
          } else if (c == "\\") {
            esc = true;
          } else if (c == '"') {
            inStr = false;
          }
        } else {
          if (c == '"') {
            inStr = true;
          } else if (c == "[") {
            depth++;
          } else if (c == "]") {
            depth--;
            if (depth == 0) {
              end = i + 1;
              break;
            }
          }
        }
      }
      if (end < 0) break;

      try {
        final data = json.decode(html.substring(start, end));
        for (var item in data) {
          if (item["slug"] == null || item["title"] == null) continue;
          MManga anime = MManga();
          anime.name = item["title"].toString();
          anime.imageUrl = (item["image"] ?? "").toString();
          final link = item["url"];
          anime.link = link != null
              ? link.toString()
              : "${source.baseUrl}/${item["slug"]}/";
          list.add(anime);
        }
      } catch (e) {}
    }
    return list;
  }

  MPages parseList(String html, int page) {
    List<MManga> list = parseEmbedded(html);

    if (list.isEmpty) {
      final document = parseHtml(html);
      var items = document.select(".anime__item");
      if (items.isEmpty) {
        items = document.select(".card");
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
          anime.imageUrl = img.attr("src");
        }
        if (anime.name.isNotEmpty && anime.link.isNotEmpty) {
          list.add(anime);
        }
      }
    }

    if (list.isEmpty) {
      throw "[v5] Sin resultados. ${describe(html)}";
    }
    final hasNext = html.contains("p=${page + 1}");
    return MPages(list, hasNext);
  }

  @override
  Future<MPages> getPopular(int page) async {
    print("[v6] 1/4 inicio getPopular page=$page");
    final html = await getHtml("/directorio?p=$page");
    print("[v6] 2/4 html recibido, largo=${html.length}");
    final embedded = parseEmbedded(html);
    print("[v6] 3/4 animes en JSON embebido=${embedded.length}");
    final result = parseList(html, page);
    print("[v6] 4/4 lista final=${result.list.length} primero=${result.list[0].name}");
    return result;
  }

  @override
  Future<MPages> getLatestUpdates(int page) async {
    final html = await getHtml("/directorio?p=$page&estado=emision");
    return parseList(html, page);
  }

  @override
  Future<MPages> search(String query, int page, FilterList filterList) async {
    final q = Uri.encodeComponent(query);
    final html = await getHtml("/buscar/$q/$page/");
    return parseList(html, page);
  }

  // ---------- DETALLE ----------
  @override
  Future<MManga> getDetail(String url) async {
    final html = await getHtml(url);
    final document = parseHtml(html);
    MManga anime = MManga();

    final nameEl = document.selectFirst("h3, h1");
    if (nameEl != null) anime.name = nameEl.text.trim();

    final bg = document.selectFirst("[data-setbg]");
    if (bg != null) anime.imageUrl = bg.attr("data-setbg");

    final desc =
        document.selectFirst("p.scroll, .sinopsis, .anime__details__text p");
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

  // ---------- VIDEO ----------
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

    for (var m
        in RegExp(r'"remote"\s*:\s*"([A-Za-z0-9+/=]+)"').allMatches(html)) {
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
        final m3u8 =
            RegExp(r'https?:[^"\s\\]+\.m3u8[^"\s\\]*').firstMatch(body);
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
    if (videos.isEmpty) {
      throw "[v5] Sin videos. Servidores encontrados: ${found.length}. ${found.join(' | ')}";
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
