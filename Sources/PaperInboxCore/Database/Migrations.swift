import Foundation

enum Migrations {
    static let version1 = """
    PRAGMA foreign_keys = ON;

    CREATE TABLE IF NOT EXISTS papers (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        authors TEXT,
        year INTEGER,
        venue TEXT,
        abstract TEXT,
        source_url TEXT,
        local_pdf_path TEXT,
        status TEXT NOT NULL,
        is_hidden INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        last_launched_at TEXT,
        last_imported_at TEXT
    );

    CREATE TABLE IF NOT EXISTS collections (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL UNIQUE,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS paper_collections (
        paper_id TEXT NOT NULL,
        collection_id TEXT NOT NULL,
        PRIMARY KEY (paper_id, collection_id),
        FOREIGN KEY (paper_id) REFERENCES papers(id) ON DELETE CASCADE,
        FOREIGN KEY (collection_id) REFERENCES collections(id) ON DELETE CASCADE
    );

    CREATE TABLE IF NOT EXISTS artifacts (
        id TEXT PRIMARY KEY,
        paper_id TEXT NOT NULL,
        type TEXT NOT NULL,
        content_markdown TEXT NOT NULL,
        source TEXT NOT NULL,
        chatgpt_url TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (paper_id) REFERENCES papers(id) ON DELETE CASCADE
    );

    CREATE VIRTUAL TABLE IF NOT EXISTS paper_search
    USING fts5(
        paper_id UNINDEXED,
        title,
        authors,
        venue,
        abstract,
        source_url,
        artifact_text
    );

    CREATE INDEX IF NOT EXISTS idx_papers_status ON papers(status);
    CREATE INDEX IF NOT EXISTS idx_artifacts_paper_id ON artifacts(paper_id);

    CREATE TABLE IF NOT EXISTS artifact_chat_links (
        paper_id TEXT NOT NULL,
        type TEXT NOT NULL,
        chatgpt_url TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        PRIMARY KEY (paper_id, type),
        FOREIGN KEY (paper_id) REFERENCES papers(id) ON DELETE CASCADE
    );

    PRAGMA user_version = 1;
    """
}
