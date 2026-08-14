"use strict";

var pluginID = "com.clipall.plugin.timestamp-tools";

function pluginError(code, message) {
  throw { code: code, message: message };
}

function pad(value, width) {
  var text = String(Math.abs(value));
  while (text.length < width) text = "0" + text;
  return text;
}

function normalizedConfiguration() {
  var configuration = App.getPluginEnv(pluginID);
  var timeZoneChoice = configuration.timeZone || "system";
  var displayFormat = configuration.displayFormat || "standard";

  if (timeZoneChoice !== "system" && timeZoneChoice !== "utc") {
    pluginError("invalid_configuration", "时区配置无效");
  }
  if (["standard", "iso8601", "chinese"].indexOf(displayFormat) === -1) {
    pluginError("invalid_configuration", "日期显示格式配置无效");
  }

  var timeZone = timeZoneChoice === "utc"
    ? "UTC"
    : Intl.DateTimeFormat().resolvedOptions().timeZone;
  if (!timeZone || typeof timeZone !== "string") {
    pluginError("invalid_environment", "无法读取系统时区");
  }

  return {
    timeZoneChoice: timeZoneChoice,
    timeZone: timeZone,
    displayFormat: displayFormat
  };
}

function partsInTimeZone(date, timeZone) {
  var formatter;
  try {
    formatter = new Intl.DateTimeFormat("en-US", {
      timeZone: timeZone,
      calendar: "gregory",
      numberingSystem: "latn",
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
      second: "2-digit",
      hourCycle: "h23"
    });
  } catch (_) {
    pluginError("invalid_environment", "系统时区不可用");
  }

  var output = {};
  formatter.formatToParts(date).forEach(function (part) {
    if (part.type !== "literal") output[part.type] = Number(part.value);
  });
  return output;
}

function offsetMinutesAt(date, timeZone) {
  if (timeZone === "UTC") return 0;
  var parts = partsInTimeZone(date, timeZone);
  var representedAsUTC = Date.UTC(
    parts.year,
    parts.month - 1,
    parts.day,
    parts.hour,
    parts.minute,
    parts.second
  );
  return Math.round((representedAsUTC - Math.floor(date.getTime() / 1000) * 1000) / 60000);
}

function offsetText(minutes) {
  var sign = minutes >= 0 ? "+" : "-";
  var absolute = Math.abs(minutes);
  return sign + pad(Math.floor(absolute / 60), 2) + ":" + pad(absolute % 60, 2);
}

function formatDate(date, timeZone, displayFormat) {
  if (!(date instanceof Date) || !Number.isFinite(date.getTime())) {
    pluginError("out_of_range", "日期超出可显示范围");
  }

  var parts = partsInTimeZone(date, timeZone);
  var datePart = pad(parts.year, 4) + "-" + pad(parts.month, 2) + "-" + pad(parts.day, 2);
  var timePart = pad(parts.hour, 2) + ":" + pad(parts.minute, 2) + ":" + pad(parts.second, 2);
  var offset = offsetText(offsetMinutesAt(date, timeZone));

  if (displayFormat === "standard") {
    return datePart + " " + timePart + " " + offset;
  }
  if (displayFormat === "chinese") {
    return pad(parts.year, 4) + "年" + pad(parts.month, 2) + "月" + pad(parts.day, 2) + "日 " + timePart;
  }
  if (timeZone === "UTC") return date.toISOString();
  return datePart + "T" + timePart + "." + pad(date.getUTCMilliseconds(), 3) + offset;
}

function validCalendarFields(year, month, day, hour, minute, second) {
  if (year < 1 || year > 9999) return false;
  if (month < 1 || month > 12 || day < 1 || day > 31) return false;
  if (hour < 0 || hour > 23 || minute < 0 || minute > 59 || second < 0 || second > 59) return false;

  var probe = new Date(0);
  probe.setUTCFullYear(year, month - 1, day);
  probe.setUTCHours(hour, minute, second, 0);
  return probe.getUTCFullYear() === year &&
    probe.getUTCMonth() === month - 1 &&
    probe.getUTCDate() === day &&
    probe.getUTCHours() === hour &&
    probe.getUTCMinutes() === minute &&
    probe.getUTCSeconds() === second;
}

function dateFromWallClock(fields, timeZone) {
  var wallClock = new Date(0);
  wallClock.setUTCFullYear(fields.year, fields.month - 1, fields.day);
  wallClock.setUTCHours(fields.hour, fields.minute, fields.second, fields.millisecond);
  var wallClockUTC = wallClock.getTime();
  var offsets = {};

  for (var deltaHours = -36; deltaHours <= 36; deltaHours += 3) {
    offsets[offsetMinutesAt(new Date(wallClockUTC + deltaHours * 3600000), timeZone)] = true;
  }

  var candidates = [];
  Object.keys(offsets).forEach(function (rawOffset) {
    var candidate = wallClockUTC - Number(rawOffset) * 60000;
    var date = new Date(candidate);
    var actual = partsInTimeZone(date, timeZone);
    if (actual.year === fields.year && actual.month === fields.month && actual.day === fields.day &&
        actual.hour === fields.hour && actual.minute === fields.minute && actual.second === fields.second &&
        date.getUTCMilliseconds() === fields.millisecond && candidates.indexOf(candidate) === -1) {
      candidates.push(candidate);
    }
  });

  if (candidates.length !== 1) {
    pluginError("invalid_input", "日期在所选时区中不存在或存在歧义");
  }
  return new Date(candidates[0]);
}

function parseExplicitISO(text) {
  var match = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,3}))?(Z|[+-]\d{2}:\d{2})$/.exec(text);
  if (!match) return null;

  var fields = {
    year: Number(match[1]),
    month: Number(match[2]),
    day: Number(match[3]),
    hour: Number(match[4]),
    minute: Number(match[5]),
    second: Number(match[6]),
    millisecond: Number((match[7] || "0") + "00".slice((match[7] || "").length))
  };
  if (!validCalendarFields(fields.year, fields.month, fields.day, fields.hour, fields.minute, fields.second)) {
    pluginError("invalid_input", "日期字段无效");
  }

  var offsetMinutes = 0;
  if (match[8] !== "Z") {
    var sign = match[8][0] === "+" ? 1 : -1;
    var offsetHour = Number(match[8].slice(1, 3));
    var offsetMinute = Number(match[8].slice(4, 6));
    if (offsetHour > 14 || offsetMinute > 59 || (offsetHour === 14 && offsetMinute !== 0)) {
      pluginError("invalid_input", "ISO 8601 时区偏移无效");
    }
    offsetMinutes = sign * (offsetHour * 60 + offsetMinute);
  }

  var wallClock = new Date(0);
  wallClock.setUTCFullYear(fields.year, fields.month - 1, fields.day);
  wallClock.setUTCHours(fields.hour, fields.minute, fields.second, fields.millisecond);
  var milliseconds = wallClock.getTime() - offsetMinutes * 60000;
  var date = new Date(milliseconds);
  if (!Number.isFinite(date.getTime())) pluginError("out_of_range", "日期超出可解析范围");
  return { date: date, assumption: null };
}

function parseLocalDate(text, timeZone) {
  var match = /^(\d{4})([-/])(\d{2})\2(\d{2})(?:( |T)(\d{2}):(\d{2}):(\d{2}))?$/.exec(text);
  if (!match) return null;
  if (match[2] === "/" && match[5] === "T") return null;

  var fields = {
    year: Number(match[1]),
    month: Number(match[3]),
    day: Number(match[4]),
    hour: match[6] ? Number(match[6]) : 0,
    minute: match[7] ? Number(match[7]) : 0,
    second: match[8] ? Number(match[8]) : 0,
    millisecond: 0
  };
  if (!validCalendarFields(fields.year, fields.month, fields.day, fields.hour, fields.minute, fields.second)) {
    pluginError("invalid_input", "日期字段无效");
  }

  return {
    date: dateFromWallClock(fields, timeZone),
    assumption: "未提供时区，按 " + timeZone + " 解释"
  };
}

function parseChineseDate(text, timeZone) {
  var match = /^(\d{4})年(\d{1,2})月(\d{1,2})日(?: (\d{2}):(\d{2}):(\d{2}))?$/.exec(text);
  if (!match) return null;

  var fields = {
    year: Number(match[1]),
    month: Number(match[2]),
    day: Number(match[3]),
    hour: match[4] ? Number(match[4]) : 0,
    minute: match[5] ? Number(match[5]) : 0,
    second: match[6] ? Number(match[6]) : 0,
    millisecond: 0
  };
  if (!validCalendarFields(fields.year, fields.month, fields.day, fields.hour, fields.minute, fields.second)) {
    pluginError("invalid_input", "日期字段无效");
  }

  return {
    date: dateFromWallClock(fields, timeZone),
    assumption: "未提供时区，按 " + timeZone + " 解释"
  };
}

function parseDateInput(text, timeZone) {
  var explicit = parseExplicitISO(text);
  if (explicit) return explicit;
  var chinese = parseChineseDate(text, timeZone);
  if (chinese) return chinese;
  var local = parseLocalDate(text, timeZone);
  if (local) return local;
  pluginError("invalid_input", "无法识别日期，请使用 ISO 8601、YYYY-MM-DD HH:mm:ss 或中文日期");
}

var ClipAllPlugin = {
  timestampToDate: function (text) {
    text = String(text || "").trim();
    var milliseconds;
    var unit;

    if (/^\d{10}$/.test(text)) {
      milliseconds = Number(text) * 1000;
      unit = "Unix 秒级时间戳";
    } else if (/^\d{13}$/.test(text)) {
      milliseconds = Number(text);
      unit = "Unix 毫秒时间戳";
    } else {
      pluginError("invalid_input", "请输入 10 位秒级或 13 位毫秒级 Unix 时间戳");
    }

    var date = new Date(milliseconds);
    if (!Number.isFinite(date.getTime())) pluginError("out_of_range", "时间戳超出可显示范围");

    var configuration = normalizedConfiguration();
    var zoneLabel = configuration.timeZoneChoice === "utc" ? "UTC" : "系统时区";
    var formatLabels = { standard: "标准", iso8601: "ISO 8601", chinese: "中文" };

    return {
      title: "时间戳 → 日期",
      subtitle: unit,
      items: [
        {
          id: "formatted",
          label: zoneLabel,
          value: formatDate(date, configuration.timeZone, configuration.displayFormat),
          annotation: configuration.timeZone + " · " + formatLabels[configuration.displayFormat],
          style: "monospaced"
        },
        {
          id: "utc",
          label: "UTC 参考",
          value: date.toISOString(),
          annotation: "ISO 8601",
          style: "monospaced"
        }
      ]
    };
  },

  dateToTimestamp: function (text) {
    text = String(text || "").trim();
    var configuration = normalizedConfiguration();
    var parsed = parseDateInput(text, configuration.timeZone);
    var milliseconds = parsed.date.getTime();
    var seconds = Math.trunc(milliseconds / 1000);

    return {
      title: "日期 → 时间戳",
      subtitle: parsed.assumption,
      items: [
        { id: "seconds", label: "秒", value: String(seconds), annotation: "Unix", style: "monospaced" },
        { id: "milliseconds", label: "毫秒", value: String(milliseconds), annotation: "Unix", style: "monospaced" },
        {
          id: "interpreted",
          label: "解释结果",
          value: formatDate(parsed.date, configuration.timeZone, configuration.displayFormat),
          annotation: configuration.timeZone,
          style: "monospaced"
        }
      ]
    };
  }
};
