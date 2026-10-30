import Foundation

/// Works out the light (golden hour, blue hour, night) from where and when a clip was filmed.
/// Uses NOAA's solar position equations, so it needs no internet connection.
enum SunCalc {
    struct Light {
        let label: String
        let tags: [String]
    }

    /// Sun elevation in degrees above the horizon, and whether it's before solar noon.
    static func elevation(at date: Date, latitude: Double, longitude: Double) -> (degrees: Double, morning: Bool) {
        let rad = Double.pi / 180
        let julianDay = date.timeIntervalSince1970 / 86400.0 + 2440587.5
        let t = (julianDay - 2451545.0) / 36525.0

        var meanLongitude = (280.46646 + t * (36000.76983 + t * 0.0003032)).truncatingRemainder(dividingBy: 360)
        if meanLongitude < 0 { meanLongitude += 360 }
        let meanAnomaly = 357.52911 + t * (35999.05029 - 0.0001537 * t)
        let eccentricity = 0.016708634 - t * (0.000042037 + 0.0000001267 * t)
        let centre = sin(meanAnomaly * rad) * (1.914602 - t * (0.004817 + 0.000014 * t))
            + sin(2 * meanAnomaly * rad) * (0.019993 - 0.000101 * t)
            + sin(3 * meanAnomaly * rad) * 0.000289
        let trueLongitude = meanLongitude + centre
        let omega = 125.04 - 1934.136 * t
        let apparentLongitude = trueLongitude - 0.00569 - 0.00478 * sin(omega * rad)
        let meanObliquity = 23.0 + (26.0 + (21.448 - t * (46.815 + t * (0.00059 - t * 0.001813))) / 60.0) / 60.0
        let obliquity = meanObliquity + 0.00256 * cos(omega * rad)
        let declination = asin(sin(obliquity * rad) * sin(apparentLongitude * rad))

        let y = pow(tan(obliquity * rad / 2), 2)
        let equationOfTime = 4 / rad * (
            y * sin(2 * meanLongitude * rad)
            - 2 * eccentricity * sin(meanAnomaly * rad)
            + 4 * eccentricity * y * sin(meanAnomaly * rad) * cos(2 * meanLongitude * rad)
            - 0.5 * y * y * sin(4 * meanLongitude * rad)
            - 1.25 * eccentricity * eccentricity * sin(2 * meanAnomaly * rad)
        )

        let dayFraction = (julianDay + 0.5) - floor(julianDay + 0.5)
        var trueSolarMinutes = (dayFraction * 1440 + equationOfTime + 4 * longitude).truncatingRemainder(dividingBy: 1440)
        if trueSolarMinutes < 0 { trueSolarMinutes += 1440 }
        var hourAngle = trueSolarMinutes / 4 - 180
        if hourAngle < -180 { hourAngle += 360 }

        let latitudeRad = latitude * rad
        let cosZenith = sin(latitudeRad) * sin(declination) + cos(latitudeRad) * cos(declination) * cos(hourAngle * rad)
        let zenith = acos(min(max(cosZenith, -1), 1)) / rad
        return (90 - zenith, hourAngle < 0)
    }

    static func light(at date: Date, latitude: Double?, longitude: Double?) -> Light {
        guard let latitude, let longitude else { return Light(label: "", tags: []) }
        let sun = elevation(at: date, latitude: latitude, longitude: longitude)
        let side = sun.morning ? "morning" : "evening"
        let sunTag = sun.morning ? "sunrise" : "sunset"
        if sun.degrees < -6 { return Light(label: "Night", tags: ["night"]) }
        if sun.degrees < 0 { return Light(label: "Blue hour (\(side))", tags: ["blue hour", sunTag]) }
        if sun.degrees < 6 { return Light(label: "Golden hour (\(side))", tags: ["golden hour", sunTag]) }
        return Light(label: "Day", tags: [])
    }
}
