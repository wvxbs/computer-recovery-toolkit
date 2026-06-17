# Privacy

The diagnostic bundle is meant to be useful for troubleshooting, which means it
can contain sensitive local context.

Common sensitive fields:

- Windows username and profile path.
- Computer name.
- Installed applications.
- Process names and command lines.
- Device model, serial-like identifiers, and driver versions.
- Event logs with timestamps and app/service names.
- Battery history and usage patterns.
- Network adapter names and configuration.
- Paths to synced folders or company tools.

Before posting a report publicly:

1. Open the generated `reports\<timestamp>` folder.
2. Search for your name, company, email, device serials, and private paths.
3. Remove files you do not want to share.
4. Prefer sending the zip privately to the person helping you.

The scripts do not upload anything by themselves.

