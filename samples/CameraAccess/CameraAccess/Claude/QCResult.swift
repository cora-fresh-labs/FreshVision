import Foundation

// MARK: - Core Result

struct QCResult: Codable {
  let imageType: String
  let commodity: String?
  let variety: String?
  let originDetected: String?
  let supplierDetected: String?
  let packaging: PackagingAssessment?
  let quality: QualityAssessment?
  let measurementsDetected: MeasurementsDetected?
  let defects: [QCDefect]
  let complianceFlags: [String]
  let overallScore: String       // GREEN, AMBER, RED
  let recommendedAction: String
  let repackRequired: Bool
  let summary: String
  let sopCoverage: SOPCoverage?
  let confidence: Double
  let error: String?

  enum CodingKeys: String, CodingKey {
    case imageType = "image_type"
    case commodity, variety
    case originDetected = "origin_detected"
    case supplierDetected = "supplier_detected"
    case packaging, quality
    case measurementsDetected = "measurements_detected"
    case defects
    case complianceFlags = "compliance_flags"
    case overallScore = "overall_score"
    case recommendedAction = "recommended_action"
    case repackRequired = "repack_required"
    case summary
    case sopCoverage = "sop_coverage"
    case confidence, error
  }
}

// MARK: - Packaging

struct PackagingAssessment: Codable {
  let outer: String?
  let inner: String?
  let primary: String?
  let packingSecure: String?
  let palletTagPresent: Bool?
  let pluPresent: String?
  let pluIssue: String?

  enum CodingKeys: String, CodingKey {
    case outer, inner, primary
    case packingSecure = "packing_secure"
    case palletTagPresent = "pallet_tag_present"
    case pluPresent = "plu_present"
    case pluIssue = "plu_issue"
  }
}

// MARK: - Quality

struct QualityAssessment: Codable {
  let colour: String?
  let eatingQuality: String?
  let size: String?
  let shape: String?
  let firmnessVisual: String?

  enum CodingKeys: String, CodingKey {
    case colour
    case eatingQuality = "eating_quality"
    case size, shape
    case firmnessVisual = "firmness_visual"
  }
}

// MARK: - Measurements

struct MeasurementsDetected: Codable {
  let temperatureF: Double?
  let temperatureC: Double?
  let brix: Double?
  let weightLbs: Double?

  enum CodingKeys: String, CodingKey {
    case temperatureF = "temperature_f"
    case temperatureC = "temperature_c"
    case brix
    case weightLbs = "weight_lbs"
  }
}

// MARK: - Defects

struct QCDefect: Codable {
  let type: String
  let severity: String          // minor, major, critical
  let estimatedPercentage: Double?
  let confidence: Double
  let location: String

  enum CodingKeys: String, CodingKey {
    case type, severity
    case estimatedPercentage = "estimated_percentage"
    case confidence, location
  }
}

// MARK: - SOP Coverage

struct SOPCoverage: Codable {
  let captured: [String]
  let stillNeeded: [String]

  enum CodingKeys: String, CodingKey {
    case captured
    case stillNeeded = "still_needed"
  }
}
