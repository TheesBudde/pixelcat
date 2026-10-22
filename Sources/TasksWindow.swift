import AppKit
import SwiftUI

/// Eigenes Fenster für die Aufgaben: eintragen, umbenennen, entfernen – und für jede einstellen,
/// wie oft sie ungefähr daran erinnert.
@MainActor
final class TasksWindow {
    private var window: NSWindow?
    private let settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
    }

    func show() {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 520),
                                  styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.minSize = NSSize(width: 480, height: 320)
            window.contentView = NSHostingView(rootView: TasksView(settings: settings))
            window.center()
            self.window = window
        }
        window?.title = L10n.s("Pixelcat – Aufgaben", "Pixelcat – Tasks")
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct TasksView: View {
    @ObservedObject var settings: AppSettings
    @State private var newText = ""
    @State private var newMinutes = TaskItem.defaultMinutes

    /// Länger passt nicht gut in die Gedankenblase (drei Zeilen)
    static let maxLength = 45

    private func t(_ de: String, _ en: String) -> String { L10n.s(de, en) }

    var body: some View {
        Form {
            Section {
                Toggle(t("An Aufgaben erinnern", "Remind me of tasks"), isOn: $settings.taskReminders)
                Toggle(t("Auch während Videocalls erinnern", "Also remind me during video calls"),
                       isOn: $settings.tasksDuringCalls)
                hint(settings.hideDuringCalls
                     ? t("Bei Kamera oder Mikrofon bleibt die Katze versteckt – nur die Blase erscheint unten am Dock. Während der Bildschirm geteilt wird, nie.",
                         "While the camera or microphone is on, the cat stays hidden – only the bubble shows up at the Dock. Never while the screen is shared.")
                     : t("Sie versteckt sich bei Videocalls nicht (Einstellungen › Rücksicht) – dann erinnert sie ohnehin.",
                         "She doesn't hide during video calls (Settings › Being considerate) – so she reminds you anyway."))
            }
            Section(t("Aufgaben", "Tasks")) {
                if settings.taskItems.isEmpty {
                    hint(t("Noch keine Aufgaben – trag unten die erste ein.", "No tasks yet – add the first one below."))
                }
                ForEach($settings.taskItems) { $task in
                    HStack(spacing: 10) {
                        TextField("", text: $task.text)
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: task.text) { value in
                                if value.count > Self.maxLength { task.text = String(value.prefix(Self.maxLength)) }
                            }
                        intervalSlider($task.minutes)
                        Button {
                            settings.onPreviewTask?(task.id)
                        } label: {
                            Image(systemName: "bubble.left")
                        }
                        .buttonStyle(.borderless)
                        .help(t("Jetzt zeigen", "Show now"))
                        Button {
                            settings.taskItems.removeAll { $0.id == task.id }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help(t("Entfernen", "Remove"))
                    }
                }
            }
            Section(t("Neue Aufgabe", "New task")) {
                HStack(spacing: 10) {
                    TextField("", text: $newText, prompt: Text(t("z. B. „Mama anrufen“", "e.g. “Call mom”")))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(add)
                        .onChange(of: newText) { value in
                            if value.count > Self.maxLength { newText = String(value.prefix(Self.maxLength)) }
                        }
                    intervalSlider($newMinutes)
                    Button(t("Hinzufügen", "Add"), action: add)
                        .disabled(newText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                hint(t("Für jede Aufgabe einzeln: Ungefähr so oft denkt sie daran – der genaue Zeitpunkt schwankt ein wenig. Im Körbchen oder auf Streifzug kommt sie dafür herein.",
                       "For each task: roughly this often she thinks of it – the exact moment varies a little. In her bed or while roaming she comes in for it."))
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 480, minHeight: 320)
        .id(settings.language)
    }

    private func add() {
        let text = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        settings.taskItems.append(TaskItem(text: text, minutes: newMinutes))
        newText = ""
    }

    private func hint(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary)
    }

    /// Schieberegler über die wählbaren Abstände, daneben z. B. „alle 2 Std.“
    private func intervalSlider(_ minutes: Binding<Int>) -> some View {
        let steps = TaskItem.intervals
        let index = Binding<Double>(
            get: { Double(steps.firstIndex { $0 >= minutes.wrappedValue } ?? steps.count - 1) },
            set: { minutes.wrappedValue = steps[min(steps.count - 1, max(0, Int($0.rounded())))] })
        return HStack(spacing: 8) {
            Slider(value: index, in: 0...Double(steps.count - 1), step: 1)
                .frame(width: 100)
            Text(Self.intervalText(minutes.wrappedValue))
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
                .frame(minWidth: 92, alignment: .leading)
        }
    }

    static func intervalText(_ minutes: Int) -> String {
        if minutes < 60 { return L10n.s("alle \(minutes) Min.", "every \(minutes) min") }
        let hours = Double(minutes) / 60
        let number = hours == hours.rounded() ? "\(Int(hours))" : String(format: "%.1f", hours)
        let german = number.replacingOccurrences(of: ".", with: ",")
        return L10n.s("alle \(german) Std.", "every \(number) h")
    }
}
