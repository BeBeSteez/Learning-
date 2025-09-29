use eframe::{egui, epi};

struct MyApp {
    counter: i32,
}

impl Default for MyApp {
    fn default() -> Self {
        Self { counter: 0 }
    }
}

impl epi::App for MyApp {
    fn name(&self) -> &str {
        "Basic Rust GUI"
    }

    fn update(&mut self, ctx: &egui::Context, _frame: &epi::Frame) {
        egui::CentralPanel::default().show(ctx, |ui| {
            ui.heading("Hello, Rust GUI!");
            if ui.button("Increment Counter").clicked() {
                self.counter += 1;
            }
            ui.label(format!("Counter value: {}", self.counter));
        });
    }
}

fn main() {
    let options = eframe::NativeOptions::default();
    eframe::run_native(
        Box::new(MyApp::default()),
        options,
    );
}
