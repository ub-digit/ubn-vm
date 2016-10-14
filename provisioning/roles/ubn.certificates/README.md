# UBNext Certificates

Puts the certificates in place for UBNext sites

## Role Variables

- ubn_cert_file: Default value is devel.crt.pem which points to a default dummy cert file in the files directory.
- ubn_key_file: Default value is devel.key.pem which points to a dummy key file in the files directory that will be used if not changed.

## Example Playbook

    - hosts: servers
      roles:
         - { role: ubn.certificates, ubn_cert_file: /path/to/cert.pem, ubn_key_file: /path/to/key.pem }
