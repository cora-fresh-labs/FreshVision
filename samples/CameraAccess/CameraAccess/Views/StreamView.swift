/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

import MWDATCore
import SwiftUI

enum QCWorkflowStep: Int, CaseIterable {
  case inspect
  case reviewEdit
  case submitSave

  var title: String {
    switch self {
    case .inspect: return "Inspect"
    case .reviewEdit: return "Review/Edit"
    case .submitSave: return "Submit/Save"
    }
  }
}

struct StreamView: View {
  @ObservedObject var viewModel: StreamSessionViewModel
  @ObservedObject var wearablesVM: WearablesViewModel
  @ObservedObject var freshVisionVM: FreshVisionViewModel

  @State private var showReportShareSheet = false
  @State private var reportShareItems: [Any] = []
  @State private var showGallerySheet = false
  @State private var showStopConfirmation = false
  @State private var workflowStep: QCWorkflowStep = .inspect
  @State private var showAPIKeyAlert = false
  @State private var apiKeyInput: String = ""

  var body: some View {
    ZStack {
      Color.black.edgesIgnoringSafeArea(.all)

      if let videoFrame = viewModel.currentVideoFrame, viewModel.hasReceivedFirstFrame {
        GeometryReader { geometry in
          Image(uiImage: videoFrame)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .edgesIgnoringSafeArea(.all)
      } else {
        VStack(spacing: 12) {
          ProgressView().scaleEffect(1.5).foregroundColor(.white)
          Text("Waiting for camera...").font(.system(size: 14)).foregroundColor(.white.opacity(0.6))
        }
      }

      VStack(spacing: 0) {
        FreshVisionTopBar(
          freshVisionVM: freshVisionVM,
          mode: viewModel.streamingMode,
          onShareSession: {
            reportShareItems = [freshVisionVM.formatSessionSummary()]
            showReportShareSheet = true
            workflowStep = .submitSave
          },
          onOpenGallery: {
            workflowStep = .reviewEdit
            showGallerySheet = true
          },
          onHome: {
            Task {
              await viewModel.stopSession()
              wearablesVM.disconnectGlasses()
            }
          },
          onAPIKey: {
            apiKeyInput = ClaudeConfig.apiKey
            showAPIKeyAlert = true
          }
        )

        WorkflowStepBar(activeStep: workflowStep)
        Text("Human-in-the-loop mode: Inspect, review notes/checklist, then create and submit report.")
          .font(.system(size: 11, weight: .medium))
          .foregroundColor(.white.opacity(0.75))
          .padding(.top, 6)

        Spacer()

        // Voice transcript overlay
        if freshVisionVM.isListening, !freshVisionVM.voiceTranscript.isEmpty {
          HStack(spacing: 8) {
            Image(systemName: "mic.fill")
              .foregroundColor(.red)
              .font(.system(size: 12))
            Text(freshVisionVM.voiceTranscript)
              .font(.system(size: 14, weight: .medium))
              .foregroundColor(.white)
              .lineLimit(3)
          }
          .padding(.horizontal, 16)
          .padding(.vertical, 10)
          .background(Color.black.opacity(0.7))
          .cornerRadius(12)
          .padding(.horizontal, 16)
          .transition(.opacity)
        }

        if let result = freshVisionVM.latestResult {
          QCResultCardView(
            result: result,
            onCopy: { _ = freshVisionVM.copyResultJSON() },
            onSpeak: { freshVisionVM.speakSummary(result.summary) },
            onShare: {
              reportShareItems = [freshVisionVM.formatReportText(result)]
              showReportShareSheet = true
            },
            onNext: {
              workflowStep = .inspect
              freshVisionVM.latestResult = nil
              if let nextItem = viewModel.dequeueCapturedPhoto() {
                Task { await freshVisionVM.inspect(using: nextItem.image, sourcePhotoId: nextItem.id) }
              }
            }
          )
          .frame(maxHeight: UIScreen.main.bounds.height * 0.55)
          .transition(.move(edge: .bottom).combined(with: .opacity))
        }

        if let error = freshVisionVM.errorMessage {
          HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.red).font(.system(size: 12))
            Text(error).font(.system(size: 12)).foregroundColor(.white).lineLimit(2)
          }
          .padding(10)
          .background(Color.red.opacity(0.2))
          .cornerRadius(10)
          .padding(.horizontal, 16)
          .onTapGesture { freshVisionVM.errorMessage = nil }
        }

        FreshVisionControls(viewModel: viewModel, freshVisionVM: freshVisionVM, onInspectTriggered: {
          workflowStep = .inspect
        }, onInspectCompleted: {
          workflowStep = .reviewEdit
        }, onReviewEdit: {
          workflowStep = .reviewEdit
          showGallerySheet = true
        }, onCreateReport: {
          workflowStep = .reviewEdit
          showGallerySheet = true
        }, onStopRequested: {
          showStopConfirmation = true
        })
      }
      .padding(.all, 16)

      if freshVisionVM.isAnalyzing || freshVisionVM.isBatchAnalyzing {
        Color.black.opacity(0.4).edgesIgnoringSafeArea(.all)
        VStack(spacing: 12) {
          ProgressView().scaleEffect(1.5).tint(.white)
          Text(freshVisionVM.isBatchAnalyzing
            ? "Analyzing \(freshVisionVM.batchPhotos.count) photos..."
            : "Analyzing..."
          )
          .font(.system(size: 16, weight: .semibold)).foregroundColor(.white)
        }
        .padding(24)
        .background(Color.black.opacity(0.7))
        .cornerRadius(16)
      }

      // Verdict bar — appears after ≥1 photo captured, before result
      if !freshVisionVM.batchPhotos.isEmpty && freshVisionVM.latestResult == nil && !freshVisionVM.isBatchAnalyzing {
        VStack(spacing: 0) {
          Spacer()
          VStack(spacing: 8) {
            Text("Would you buy this?")
              .font(.system(size: 13, weight: .semibold))
              .foregroundColor(.white.opacity(0.9))
            HStack(spacing: 12) {
              Button(action: { Task { await freshVisionVM.submitWithVerdict(.yes) } }) {
                VStack(spacing: 4) {
                  Text("✅").font(.system(size: 22))
                  Text("YES").font(.system(size: 11, weight: .bold)).foregroundColor(.green)
                }
                .padding(.horizontal, 22).padding(.vertical, 10)
                .background(Color.green.opacity(0.25))
                .cornerRadius(12)
              }
              Button(action: { Task { await freshVisionVM.submitWithVerdict(.maybe) } }) {
                VStack(spacing: 4) {
                  Text("🟡").font(.system(size: 22))
                  Text("MAYBE").font(.system(size: 11, weight: .bold)).foregroundColor(.yellow)
                }
                .padding(.horizontal, 18).padding(.vertical, 10)
                .background(Color.yellow.opacity(0.2))
                .cornerRadius(12)
              }
              Button(action: { Task { await freshVisionVM.submitWithVerdict(.no) } }) {
                VStack(spacing: 4) {
                  Text("❌").font(.system(size: 22))
                  Text("NO").font(.system(size: 11, weight: .bold)).foregroundColor(.red)
                }
                .padding(.horizontal, 22).padding(.vertical, 10)
                .background(Color.red.opacity(0.2))
                .cornerRadius(12)
              }
            }
            Text("\(freshVisionVM.batchPhotos.count) photo\(freshVisionVM.batchPhotos.count == 1 ? "" : "s") captured")
              .font(.system(size: 10))
              .foregroundColor(.white.opacity(0.5))
          }
          .padding(.vertical, 12)
          .padding(.horizontal, 20)
          .background(Color.black.opacity(0.75))
          .cornerRadius(16)
          .padding(.bottom, 100)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
      }
    }
    .animation(.easeInOut(duration: 0.3), value: freshVisionVM.latestResult != nil)
    .animation(.easeInOut(duration: 0.2), value: freshVisionVM.isListening)
    .onDisappear {
      Task {
        if viewModel.streamingStatus != .stopped { await viewModel.stopSession() }
        freshVisionVM.stopSpeaking()
        freshVisionVM.stopListening()
      }
    }
    .sheet(isPresented: $viewModel.showPhotoPreview) {
      if let photo = viewModel.capturedPhoto {
        PhotoPreviewView(photo: photo, onDismiss: { viewModel.dismissPhotoPreview() })
      }
    }
    .sheet(isPresented: $showReportShareSheet) {
      ReportShareSheet(items: reportShareItems)
    }
    .sheet(isPresented: $showGallerySheet) {
      ReportFinalizationSheet(
        freshVisionVM: freshVisionVM,
        onInspectNext: {
          workflowStep = .inspect
          if let nextItem = viewModel.dequeueCapturedPhoto() {
            Task { await freshVisionVM.inspect(using: nextItem.image, sourcePhotoId: nextItem.id) }
          }
        },
        onFinalize: { workflowStep = .submitSave },
        onShareItems: { items in
          workflowStep = .submitSave
          reportShareItems = items
          showReportShareSheet = true
        }
      )
    }
    .alert("End inspection stream?", isPresented: $showStopConfirmation) {
      Button("Keep Streaming", role: .cancel) {}
      Button("Stop Stream", role: .destructive) {
        Task { await viewModel.stopSession() }
      }
    } message: {
      Text("This will stop the live feed. Your captured photos, notes, and review progress stay in this session.")
    }
    .alert("Claude API Key", isPresented: $showAPIKeyAlert) {
      TextField("sk-ant-...", text: $apiKeyInput)
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
      Button("Save") {
        let trimmed = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
          ClaudeConfig.apiKey = trimmed
        }
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text(ClaudeConfig.isConfigured
           ? "API key is set. Enter a new key to replace it."
           : "Enter your Anthropic API key from console.anthropic.com")
    }
  }
}

struct WorkflowStepBar: View {
  let activeStep: QCWorkflowStep

  var body: some View {
    HStack(spacing: 6) {
      ForEach(Array(QCWorkflowStep.allCases.enumerated()), id: \.element) { index, step in
        let isActive = step == activeStep
        let isDone = index < QCWorkflowStep.allCases.firstIndex(of: activeStep)!
        Text(step.title)
          .font(.system(size: 10, weight: .semibold))
          .foregroundColor(isActive || isDone ? .white : .white.opacity(0.5))
          .padding(.horizontal, 10)
          .padding(.vertical, 4)
          .background(isActive ? Color.green.opacity(0.4) : (isDone ? Color.green.opacity(0.2) : Color.white.opacity(0.08)))
          .cornerRadius(10)
      }
    }
    .padding(.top, 8)
  }
}

struct FreshVisionTopBar: View {
  @ObservedObject var freshVisionVM: FreshVisionViewModel
  let mode: StreamingMode
  var onShareSession: (() -> Void)?
  var onOpenGallery: (() -> Void)?
  var onHome: (() -> Void)?
  var onAPIKey: (() -> Void)?

  var body: some View {
    VStack(spacing: 6) {
      HStack {
        Button(action: { onHome?() }) {
          Image(systemName: "house.fill")
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(.white)
            .padding(8)
            .background(Color.black.opacity(0.6))
            .cornerRadius(12)
        }

        HStack(spacing: 6) {
          Image(systemName: "leaf.fill").font(.system(size: 12)).foregroundColor(.green)
          Text("FreshVision").font(.system(size: 14, weight: .bold)).foregroundColor(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.6))
        .cornerRadius(16)

        // API Key status button
        Button(action: { onAPIKey?() }) {
          Image(systemName: "key.fill")
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(ClaudeConfig.isConfigured ? .green : .red)
            .padding(7)
            .background(Color.black.opacity(0.6))
            .cornerRadius(10)
        }

        Spacer()

        Button(action: { onOpenGallery?() }) {
          HStack(spacing: 4) {
            Image(systemName: "photo.on.rectangle.angled")
            Text("\(freshVisionVM.sessionPhotos.count)")
              .font(.system(size: 11, weight: .bold, design: .monospaced))
          }
          .font(.system(size: 11, weight: .medium))
          .foregroundColor(.white)
          .padding(.horizontal, 10)
          .padding(.vertical, 5)
          .background(Color.white.opacity(0.15))
          .cornerRadius(12)
        }

        HStack(spacing: 4) {
          Image(systemName: mode == .iPhone ? "iphone" : "eyeglasses").font(.system(size: 11))
          Text(mode == .iPhone ? "iPhone" : "Glasses").font(.system(size: 11, weight: .medium))
        }
        .foregroundColor(.white.opacity(0.7))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.black.opacity(0.4))
        .cornerRadius(12)

        if freshVisionVM.inspectionHistory.count >= 2 {
          Button(action: { onShareSession?() }) {
            HStack(spacing: 4) {
              Text("\(freshVisionVM.inspectionHistory.count)")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
              Image(systemName: "square.and.arrow.up").font(.system(size: 10))
            }
            .foregroundColor(.white)
            .frame(height: 28)
            .padding(.horizontal, 10)
            .background(Color.white.opacity(0.2))
            .cornerRadius(14)
          }
        }
      }

      if !freshVisionVM.sessionCaptured.isEmpty {
        SessionSOPBar(captured: freshVisionVM.sessionCaptured)
      }
    }
  }
}

struct SessionSOPBar: View {
  let captured: Set<String>
  private let allSteps = ["label", "fruit_topdown", "defect_closeup", "cut_fruit", "temperature_reading", "brix_reading", "weight_check"]

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 4) {
        ForEach(allSteps, id: \.self) { step in
          let done = captured.contains(step)
          HStack(spacing: 2) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle").font(.system(size: 8)).foregroundColor(done ? .green : .white.opacity(0.3))
            Text(step.replacingOccurrences(of: "_", with: " ").capitalized).font(.system(size: 9)).foregroundColor(done ? .white.opacity(0.9) : .white.opacity(0.3))
          }
          .padding(.horizontal, 5)
          .padding(.vertical, 3)
          .background(done ? Color.green.opacity(0.15) : Color.clear)
          .cornerRadius(6)
        }
      }
    }
    .padding(.horizontal, 4)
    .padding(.vertical, 4)
    .background(Color.black.opacity(0.5))
    .cornerRadius(10)
  }
}

struct FreshVisionControls: View {
  @ObservedObject var viewModel: StreamSessionViewModel
  @ObservedObject var freshVisionVM: FreshVisionViewModel
  var onInspectTriggered: (() -> Void)?
  var onInspectCompleted: (() -> Void)?
  var onReviewEdit: (() -> Void)?
  var onCreateReport: (() -> Void)?
  var onStopRequested: (() -> Void)?

  var body: some View {
    VStack(spacing: 10) {

      // MARK: Verdict bar — appears once ≥1 batch photo captured
      if !freshVisionVM.batchPhotos.isEmpty && freshVisionVM.latestResult == nil {
        VStack(spacing: 6) {
          HStack(spacing: 4) {
            Image(systemName: "camera.badge.checkmark").font(.system(size: 11)).foregroundColor(.white.opacity(0.7))
            Text("\(freshVisionVM.batchPhotos.count) photo\(freshVisionVM.batchPhotos.count == 1 ? "" : "s") captured")
              .font(.system(size: 11, weight: .medium)).foregroundColor(.white.opacity(0.7))
          }
          Text("Would you buy this?")
            .font(.system(size: 14, weight: .bold)).foregroundColor(.white)
          HStack(spacing: 12) {
            ForEach([InspectorVerdict.yes, .maybe, .no], id: \.label) { verdict in
              Button(action: { Task { await freshVisionVM.submitWithVerdict(verdict) } }) {
                VStack(spacing: 3) {
                  Text(verdict.emoji).font(.system(size: 22))
                  Text(verdict.label).font(.system(size: 10, weight: .bold))
                    .foregroundColor(verdict == .yes ? .green : verdict == .maybe ? .yellow : .red)
                }
                .padding(.horizontal, 18).padding(.vertical, 8)
                .background(
                  (verdict == .yes ? Color.green : verdict == .maybe ? Color.yellow : Color.red).opacity(0.18)
                )
                .cornerRadius(12)
              }
              .disabled(freshVisionVM.isBatchAnalyzing)
            }
          }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color.black.opacity(0.55))
        .cornerRadius(16)
      }

      // Batch analyzing overlay
      if freshVisionVM.isBatchAnalyzing {
        HStack(spacing: 8) {
          ProgressView().tint(.white).scaleEffect(0.9)
          Text("Analyzing \(freshVisionVM.batchPhotos.count) photos...")
            .font(.system(size: 13, weight: .semibold)).foregroundColor(.white)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(Color.black.opacity(0.7)).cornerRadius(12)
      }

      HStack(spacing: 8) {
        CustomButton(title: "Stop", style: .destructive, isDisabled: false) {
          onStopRequested?()
        }
        .frame(maxWidth: 96)

        Button(action: { onReviewEdit?() }) {
          Label("Review/Edit", systemImage: "square.and.pencil")
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.16))
            .cornerRadius(14)
        }

        Button(action: { onCreateReport?() }) {
          Label("Create Report", systemImage: "doc.badge.plus")
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.black)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.white)
            .cornerRadius(14)
        }
      }

      HStack(spacing: 12) {
        if freshVisionVM.isSpeaking {
          Button(action: { freshVisionVM.stopSpeaking() }) {
            HStack(spacing: 4) {
              Image(systemName: "speaker.wave.2.fill").font(.system(size: 12))
              SpeakingIndicator()
            }
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.5))
            .cornerRadius(20)
          }
        }

        // Mic button for voice input
        Button(action: {
          if freshVisionVM.isListening {
            freshVisionVM.stopListening()
          } else {
            freshVisionVM.startListening()
          }
        }) {
          Image(systemName: freshVisionVM.isListening ? "mic.fill" : "mic")
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(freshVisionVM.isListening ? .white : .white.opacity(0.7))
            .padding(12)
            .background(freshVisionVM.isListening ? Color.red.opacity(0.7) : Color.black.opacity(0.5))
            .clipShape(Circle())
        }

        Button(action: {
          onInspectTriggered?()
          Task {
            if let nextItem = viewModel.dequeueCapturedPhoto() {
              await freshVisionVM.inspect(using: nextItem.image, sourcePhotoId: nextItem.id)
            } else {
              await freshVisionVM.inspect()
            }
            if freshVisionVM.latestResult != nil {
              onInspectCompleted?()
            }
          }
        }) {
          HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 16, weight: .semibold))
            Text("Inspect").font(.system(size: 15, weight: .bold))
          }
          .foregroundColor(.black)
          .padding(.horizontal, 24)
          .padding(.vertical, 14)
          .background(Color(red: 0, green: 176.0 / 255.0, blue: 80.0 / 255.0))
          .cornerRadius(28)
        }
        .disabled(freshVisionVM.isAnalyzing)
        .opacity(freshVisionVM.isAnalyzing ? 0.5 : 1.0)

        ZStack(alignment: .topTrailing) {
          CircleButton(icon: "camera.fill", text: nil) { viewModel.capturePhoto() }

          if !viewModel.capturedPhotos.isEmpty {
            Text("\(viewModel.capturedPhotos.count)")
              .font(.system(size: 10, weight: .bold))
              .foregroundColor(.white)
              .padding(.horizontal, 6)
              .padding(.vertical, 2)
              .background(Color.red)
              .clipShape(Capsule())
              .offset(x: 8, y: -8)
          }
        }
      }
    }
    .padding(.top, 8)
  }
}

struct ReportFinalizationSheet: View {
  @Environment(\.dismiss) private var dismiss
  @ObservedObject var freshVisionVM: FreshVisionViewModel
  var onInspectNext: () -> Void
  var onFinalize: () -> Void
  var onShareItems: ([Any]) -> Void

  @State private var saveMessage: String?

  private let grid = [GridItem(.adaptive(minimum: 92), spacing: 8)]

  var body: some View {
    NavigationView {
      VStack(spacing: 10) {
        if freshVisionVM.sessionPhotos.isEmpty {
          Text("No captured photos yet. You can still complete notes/checklist and create a report from inspected frames.")
            .font(.system(size: 14))
            .foregroundColor(.secondary)
            .padding()
        } else {
          ScrollView {
            LazyVGrid(columns: grid, spacing: 8) {
              ForEach(freshVisionVM.sessionPhotos) { item in
                ZStack(alignment: .topTrailing) {
                  Image(uiImage: item.image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 92)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .overlay(
                      RoundedRectangle(cornerRadius: 8)
                        .stroke(freshVisionVM.heroPhotoID == item.id ? Color.yellow : (freshVisionVM.selectedPhotoIDs.contains(item.id) ? Color.green : Color.clear), lineWidth: 3)
                    )
                    .cornerRadius(8)
                    .onTapGesture { freshVisionVM.togglePhotoSelection(item.id) }
                    .onLongPressGesture { freshVisionVM.setHeroPhoto(item.id) }

                  if freshVisionVM.selectedPhotoIDs.contains(item.id) {
                    Image(systemName: freshVisionVM.heroPhotoID == item.id ? "star.circle.fill" : "checkmark.circle.fill")
                      .foregroundColor(freshVisionVM.heroPhotoID == item.id ? .yellow : .green)
                      .padding(4)
                  }
                }
              }
            }
            .padding(.horizontal)
          }

          HStack {
            Text("Selected: \(freshVisionVM.selectedPhotoIDs.count)")
            Spacer()
            Text("Hero: \(freshVisionVM.heroPhotoID != nil ? "Set" : "Not set")")
          }
          .font(.system(size: 13, weight: .medium))
          .padding(.horizontal)
        }

        VStack(alignment: .leading, spacing: 8) {
          Text("Inspector Notes")
            .font(.system(size: 14, weight: .semibold))
          TextEditor(text: $freshVisionVM.inspectorNotes)
            .frame(minHeight: 84)
            .padding(6)
            .background(Color.black.opacity(0.35))
            .cornerRadius(8)
        }
        .padding(.horizontal)

        VStack(alignment: .leading, spacing: 6) {
          Text("Manual Checklist")
            .font(.system(size: 14, weight: .semibold))

          ForEach(Array(freshVisionVM.inspectorChecklist.indices), id: \.self) { index in
            Toggle(
              freshVisionVM.inspectorChecklist[index].title,
              isOn: Binding(
                get: { freshVisionVM.inspectorChecklist[index].isChecked },
                set: { freshVisionVM.inspectorChecklist[index].isChecked = $0 }
              )
            )
            .toggleStyle(.switch)
          }
        }
        .padding(.horizontal)

        if let msg = saveMessage {
          Text(msg).font(.system(size: 12)).foregroundColor(.secondary).padding(.horizontal)
        }

        VStack(spacing: 8) {
          Button("Inspect Next Captured") { onInspectNext() }
            .buttonStyle(.bordered)

          Button("Create Report") {
            onFinalize()
            guard let payload = freshVisionVM.finalizeReportPayload() else { return }
            let pdf = freshVisionVM.generateReportPDFData(text: payload.reportText)
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyyMMdd-HHmmss"
            let stamp = dateFormatter.string(from: Date())
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("FreshVision-QA-Report-\(stamp).pdf")
            try? pdf.write(to: tempURL)
            onShareItems([payload.reportText, tempURL])
          }
          .buttonStyle(.borderedProminent)
          .disabled(!freshVisionVM.canFinalizeReport)

          HStack {
            Button("Share Text") {
              guard let text = freshVisionVM.finalizedReportText else { return }
              onShareItems([text])
            }
            .buttonStyle(.bordered)
            .disabled(freshVisionVM.finalizedReportText == nil)

            Button("Save to Device") {
              guard let text = freshVisionVM.finalizedReportText else { return }
              do {
                let pdf = freshVisionVM.generateReportPDFData(text: text)
                _ = try freshVisionVM.saveReportToDocuments(text: text, pdfData: pdf)
                freshVisionVM.saveSelectedPhotosToLibrary()
                saveMessage = "Saved report to Files (Documents) + selected photos to Photos."
              } catch {
                saveMessage = "Save failed: \(error.localizedDescription)"
              }
            }
            .buttonStyle(.bordered)
            .disabled(freshVisionVM.finalizedReportText == nil)
          }
        }
        .padding(.bottom)
      }
      .navigationTitle("Review & Submit")
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("Close") { dismiss() }
        }
      }
    }
  }
}
