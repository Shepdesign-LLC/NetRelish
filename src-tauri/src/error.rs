use serde::{Serialize, Serializer};

#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error("{0}")]
    Io(#[from] std::io::Error),

    #[error("{0}")]
    Tauri(#[from] tauri::Error),

    #[error("not a valid url: {0}")]
    BadUrl(String),

    #[error("{0} is outside the project directory")]
    OutsideProject(String),

    #[error("no project is open")]
    NoProject,
}

// Surface a plain string to the frontend rather than a serde-tagged enum.
impl Serialize for Error {
    fn serialize<S: Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        serializer.serialize_str(&self.to_string())
    }
}

pub type Result<T> = std::result::Result<T, Error>;
