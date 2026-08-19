//! Proves the Keychain patterns commands/credentials.rs relies on:
//! create-with-label, update-on-duplicate, enumerate-by-label, read, delete.
//! Uses the reserved `test.invalid` host and removes everything it makes.
//! Run with: cargo test --test keychain

use security_framework::item::{ItemClass, ItemSearchOptions, Limit, SearchResult};
use security_framework::passwords::{
    delete_generic_password, get_generic_password, set_generic_password_options,
};
use security_framework::passwords_options::PasswordOptions;

const SERVICE: &str = "NetRelish: test.invalid";
const ACCOUNT: &str = "nr-test-user";

fn save(secret: &[u8]) {
    let mut options = PasswordOptions::new_generic_password(SERVICE, ACCOUNT);
    options.set_label("NetRelish");
    options.set_description("NetRelish login");
    set_generic_password_options(secret, options).expect("keychain save");
}

#[test]
fn keychain_round_trip() {
    save(b"nr-test-secret");
    assert_eq!(
        get_generic_password(SERVICE, ACCOUNT).expect("read back"),
        b"nr-test-secret"
    );

    // A second save for the same (service, account) must replace, not error —
    // credential_save_from_page depends on this for "update password".
    save(b"nr-test-secret-2");
    assert_eq!(
        get_generic_password(SERVICE, ACCOUNT).expect("read after update"),
        b"nr-test-secret-2"
    );

    // credential_list finds items by the shared label.
    let found = ItemSearchOptions::new()
        .class(ItemClass::generic_password())
        .label("NetRelish")
        .load_attributes(true)
        .limit(Limit::All)
        .search()
        .expect("label search");
    let hit = found
        .iter()
        .filter_map(SearchResult::simplify_dict)
        .any(|d| {
            d.get("svce").map(String::as_str) == Some(SERVICE)
                && d.get("acct").map(String::as_str) == Some(ACCOUNT)
        });
    assert!(hit, "label search must surface the saved item");

    // And per-host enumeration by service.
    let by_service = ItemSearchOptions::new()
        .class(ItemClass::generic_password())
        .service(SERVICE)
        .load_attributes(true)
        .limit(Limit::All)
        .search()
        .expect("service search");
    assert!(!by_service.is_empty(), "service search must find the host's items");

    delete_generic_password(SERVICE, ACCOUNT).expect("delete");
    assert!(
        get_generic_password(SERVICE, ACCOUNT).is_err(),
        "item must be gone after delete"
    );
}
