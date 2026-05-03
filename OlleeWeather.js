// OlleeWeather.js
// Scriptable script for iOS
// Fetches Open-Meteo forecast and encodes it as 6 characters
// for the OlleeSplash Shortcuts action.
//
// Encoding:
//   Morning (08-12) : 2 chars
//   Mid-day (12-16) : 2 chars
//   Evening (16-20) : 2 chars
//   Char 1 of each pair = temp bucket (a-g)
//   Char 2 of each pair = precipitation probability 0-9 (deciles, max of block)
//
// Temp buckets:
//   a = below 0°C
//   b = 0 – 4°C
//   c = 5 – 9°C
//   d = 10 – 14°C
//   e = 15 – 19°C
//   f = 20 – 24°C
//   g = 25°C and above

function parseLatLon(input) {
  if (!input) throw new Error("Missing location parameter. Pass lat,lon (e.g. 51.5074,-0.1278).")
  const parts = String(input).split(/[,; ]+/)
  const lat = parseFloat(parts[0])
  const lon = parseFloat(parts[1])
  if (isNaN(lat) || isNaN(lon)) {
    throw new Error("Invalid location parameter. Pass lat,lon (e.g. 51.5074,-0.1278).")
  }
  return { lat, lon }
}

const param = args.shortcutParameter
const { lat, lon } = parseLatLon(param)

function tempBucket(temp) {
  if (temp < 0) return "a"
  if (temp < 5) return "b"
  if (temp < 10) return "c"
  if (temp < 15) return "d"
  if (temp < 20) return "e"
  if (temp < 25) return "f"
  return "g"
}

function precipDigit(prob) {
  const p = Math.max(0, Math.min(9, Math.round(prob / 10)))
  return String(p)
}

async function fetchWeather() {
  const url = `https://api.open-meteo.com/v1/forecast?latitude=${lat}&longitude=${lon}&hourly=temperature_2m,precipitation_probability&forecast_days=1&timezone=Europe/Zurich`

  const req = new Request(url)
  const data = await req.loadJSON()

  if (!data.hourly) {
    throw new Error("No hourly data from weather API")
  }

  const times = data.hourly.time
  const temps = data.hourly.temperature_2m
  const probs = data.hourly.precipitation_probability

  function encodeBlock(startHour, endHour, label) {
    let minTemp = Infinity
    let maxProb = -Infinity
    let count = 0

    for (let i = 0; i < times.length; i++) {
      const hour = parseInt(times[i].slice(11, 13), 10)
      if (hour >= startHour && hour < endHour) {
        const t = temps[i]
        const p = probs[i] ?? 0
        if (t != null) {
          minTemp = Math.min(minTemp, t)
        }
        if (p != null) {
          maxProb = Math.max(maxProb, p)
        }
        count++
      }
    }

    if (count === 0) {
      throw new Error(`No data for ${label} block`)
    }

    if (minTemp === Infinity) minTemp = 15
    if (maxProb === -Infinity) maxProb = 0

    return tempBucket(minTemp) + precipDigit(maxProb)
  }

  const morning = encodeBlock(8, 12, "morning")
  const midday  = encodeBlock(12, 16, "midday")
  const evening = encodeBlock(16, 20, "evening")

  return morning + midday + evening
}

try {
  const encoded = await fetchWeather()
  Script.setShortcutOutput(encoded)
} catch (err) {
  const alert = new Alert()
  alert.title = "Weather Error"
  alert.message = err.message
  alert.addAction("OK")
  await alert.present()
  Script.setShortcutOutput("ERROR")
}
