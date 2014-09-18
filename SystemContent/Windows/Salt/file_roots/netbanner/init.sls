{% from "netbanner/map.jinja" import netbanner with context %}

#Install and Apply Netbanner Settings
Netbanner:
  pkg:
    - installed
    - version: {{ netbanner.version }}

NetBanner.admx:
  file:
    - managed
    - name: {{ netbanner.admx_name }}
    - source: {{ netbanner.admx_source }}
    - require:
      - pkg: Netbanner

NetBanner.adml:
  file:
    - managed
    - name: {{ netbanner.adml_name }}
    - source: {{ netbanner.adml_source }}
    - require:
      - pkg: Netbanner

CustomSettings:
  reg:
    - present
    - name: 'HKEY_LOCAL_MACHINE\\SOFTWARE\\Policies\\Microsoft\\NetBanner\\CustomSettings'
    - value: {{ netbanner.CustomSettings }}
    - vtype: REG_DWORD
    - reflection: True
    
CustomBackgroundColor:
  reg:
    - present
    - name: 'HKEY_LOCAL_MACHINE\\SOFTWARE\\Policies\\Microsoft\\NetBanner\\CustomBackgroundColor'
    - value: {{ netbanner.CustomBackgroundColor }}
    - vtype: REG_DWORD
    - reflection: True

CustomForeColor:
  reg:
    - present
    - name: 'HKEY_LOCAL_MACHINE\\SOFTWARE\\Policies\\Microsoft\\NetBanner\\CustomForeColor'
    - value: {{ netbanner.CustomForeColor }}
    - vtype: REG_DWORD
    - reflection: True

CustomDisplayText:
  reg:
    - present
    - name: 'HKEY_LOCAL_MACHINE\\SOFTWARE\\Policies\\Microsoft\\NetBanner\\CustomDisplayText'
    - value: '{{ netbanner.CustomDisplayText }}'
    - vtype: REG_SZ
    - reflection: True
