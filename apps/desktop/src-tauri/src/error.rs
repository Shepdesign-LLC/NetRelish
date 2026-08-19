use serde::{Serialize, Serializer};

#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error("{0}")]
    Io(#[from] std::io::Error),

    #[error("{0}")]
    Tauri(#[from] tauri::Error),

    #[error("not a valid url: {0}")]
    BadUrl(String),

    #[error("no jar is open")]
    NoJar,

    #[error("no page is open")]
    NoPage,

    #[error("engine: {0}")]
    Engine(String),

    // Never carries credential material — hosts and OSStatus text only.
    #[error("{0}")]
    Keychain(String),
}

impl From<security_framework::base::Error> for Error {
    fn from(e: security_framework::base::Error) -> Self {
        Error::Keychain(format!("keychain: {e}"))
    }
}

// Surface a plain string to the frontend rather than a serde-tagged enum.
impl Serialize for Error {
    fn serialize<S: Serializer>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error> {
        serializer.serialize_str(&self.to_string())
    }
}

pub type Result<T> = std::result::Result<T, Error>;
