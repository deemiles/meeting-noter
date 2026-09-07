// Recording diagnostics: the tracks and the loudness (RMS/peak) of each audio track.
// Usage: swift scripts/analyze-recording.swift <path to .mov>
import AVFoundation

let args = CommandLine.arguments
guard args.count > 1 else { fatalError("usage: analyze-recording.swift <file.mov>") }
let url = URL(fileURLWithPath: args[1])

let semaphore = DispatchSemaphore(value: 0)

Task {
    let asset = AVURLAsset(url: url)
    let duration = try await asset.load(.duration)
    print(String(format: "Duration: %.1f s", duration.seconds))

    let videoTracks = try await asset.loadTracks(withMediaType: .video)
    for track in videoTracks {
        let size = try await track.load(.naturalSize)
        let fps = try await track.load(.nominalFrameRate)
        print(String(format: "Video: %.0fx%.0f @ %.1f fps", size.width, size.height, fps))
    }

    let audioTracks = try await asset.loadTracks(withMediaType: .audio)
    print("Audio tracks: \(audioTracks.count)")

    for (index, track) in audioTracks.enumerated() {
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
        ])
        reader.add(output)
        reader.startReading()

        var sumSquares = 0.0
        var peak: Float = 0
        var count = 0
        var loudSamples = 0 // samples louder than -40 dB

        while let sampleBuffer = output.copyNextSampleBuffer() {
            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }
            let length = CMBlockBufferGetDataLength(blockBuffer)
            var data = [Float](repeating: 0, count: length / 4)
            data.withUnsafeMutableBytes { ptr in
                _ = CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: ptr.baseAddress!)
            }
            for sample in data {
                sumSquares += Double(sample * sample)
                peak = max(peak, abs(sample))
                if abs(sample) > 0.01 { loudSamples += 1 }
            }
            count += data.count
        }

        let rms = count > 0 ? (sumSquares / Double(count)).squareRoot() : 0
        let rmsDB = rms > 0 ? 20 * log10(rms) : -120
        let peakDB = peak > 0 ? 20 * log10(Double(peak)) : -120
        let loudPercent = count > 0 ? Double(loudSamples) / Double(count) * 100 : 0
        print(String(
            format: "  Track %d: RMS %.1f dB, peak %.1f dB, audible share %.1f%%, samples %d",
            index + 1, rmsDB, peakDB, loudPercent, count
        ))
    }
    semaphore.signal()
}

semaphore.wait()
