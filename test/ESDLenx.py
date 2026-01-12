import requests
import xml.etree.ElementTree as ET
import json
import sys
import re
import time
import os
import struct
#from requests.exceptions import RequestException, Timeout, ConnectionError

MODE = 1  # 0 = single scan mode, 1 = batch mode
INPUT_FILE = 'editions.js'
OUTPUT_FILE = 'editions.js'
MAX_RETRIES = 3
RETRY_DELAY = 2
HEADERS = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
}
URL_CACHE = {}

def fetch_bytes(url, start, end):
    h_range = HEADERS.copy()
    h_range['Range'] = f'bytes={start}-{end}'
    
    response = requests.get(url, headers=h_range, stream=True, timeout=15)
    if response.status_code == 206:
        return response.content
    elif response.status_code == 200:
        raise Exception("HTTP 200 (Full File Sent - Rnge ignored)")
    elif response.status_code in [403, 404]:
        raise Exception(f"HTTP {response.status_code} (Dead Link)")
    
    raise Exception(f"HTTP {response.status_code}")

def xml_to_dict(element):
    node = {}
    if element.attrib:
        node.update(element.attrib)

    text = element.text
    if text and text.strip():
        if not element.attrib and len(element) == 0: 
            return text.strip()
        node['text'] = text.strip()

    for child in element:
        child_data = xml_to_dict(child)
        if child.tag in node:
            if not isinstance(node[child.tag], list): 
                node[child.tag] = [node[child.tag]]
            node[child.tag].append(child_data)
        else:
            node[child.tag] = child_data
    return node

def clean_image_info(raw_images):
    clean_list = []
    arch_map = {'0': 'x86', '9': 'x64', '12': 'ARM64'}

    edition_map = {
        "Core": "Windows 11 Home",
        "CoreSingleLanguage": "Windows 11 Home Single Language",
        "CoreCountrySpecific": "Windows 11 Home China",
        "Professional": "Windows 11 Pro",
        "ProfessionalN": "Windows 11 Pro N",
        "ProfessionalWorkstation": "Windows 11 Pro for Workstations",
        "Education": "Windows 11 Education",
        "Enterprise": "Windows 11 Enterprise",
        "IoTEnterprise": "Windows 11 IoT Enterprise",
        "ServerRdsh": "Windows 11 Enterprise multi-session",
        "WindowsPE": "Windows Setup / PE Environment"
    }

    for img in raw_images:
        win = img.get('WINDOWS', {})
        ver_raw = win.get('VERSION', {})
        
        if isinstance(ver_raw, dict):
            build_str = f"{ver_raw.get('MAJOR','10')}.{ver_raw.get('MINOR','0')}.{ver_raw.get('BUILD','0')}.{ver_raw.get('SPBUILD','0')}"
        else:
            build_str = "Unknown"
        
        install_type = win.get('INSTALLATIONTYPE', 'Unknown')
        readable_type = "Boot / Setup Media" if install_type.lower() == 'windowspe' else "Operating System"
        langs = win.get('LANGUAGES', {})
        lang_code = langs.get('DEFAULT', 'N/A') if isinstance(langs, dict) else "N/A"
        bytes_val = int(img.get('TOTALBYTES', 0))
        #size_str = f"{bytes_val / (1024**3):.2f} GB" if bytes_val > 1024**3 else f"{bytes_val / (1024**2):.0f} MB"
        eid = win.get('EDITIONID', 'Unknown')
        original_name = img.get('DISPLAYNAME') or img.get('NAME', 'Unknown')
        
        if eid in edition_map:
            final_name = edition_map[eid]
            #final_desc = final_name
        else:
            if "Setup" in original_name or install_type.lower() == 'windowspe':
                 final_name = "Windows Setup Media"
                 #final_desc = "Windows Setup Media"
            else:
                 final_name = original_name
                 #final_desc = img.get('DISPLAYDESCRIPTION') or img.get('DESCRIPTION', '')

        clean_list.append({
            "index": int(img.get('INDEX', 0)),
            "name": final_name,
            "edition_id": eid,
            "type": readable_type,
            "arch": arch_map.get(win.get('ARCH', '?'), '?'),
            "build": build_str,
            "lang": lang_code,
            "size": bytes_val
        })
    return clean_list

def scan_esd_native(url):
    print(f"reading Header...", end="\r")
    
    attempts = 0
    while attempts < MAX_RETRIES:
        try:
            header_data = fetch_bytes(url, 0, 208)
            
            if header_data[0:5] != b'MSWIM':
                 return {"status": "error", "message": "Invalid (Not a WIM/ESD)"}

            res_header = header_data[72:96]
            offset_raw = res_header[8:16]
            original_size_raw = res_header[16:24]
            xml_offset = struct.unpack('<Q', offset_raw)[0]
            xml_size = struct.unpack('<Q', original_size_raw)[0]
            
            if xml_offset == 0 or xml_size == 0:
                 return {"status": "encrypted", "message": "Header Encrypted/Empty"}

            print(f"fetching XML at {xml_offset}...", end="\r")
            xml_data = fetch_bytes(url, xml_offset, xml_offset + xml_size - 1)

            try:
                xml_str = xml_data.decode('utf-16le')
                if xml_str.startswith('\ufeff'): xml_str = xml_str[1:]
            except:
                xml_str = xml_data.decode('utf-8', errors='ignore')

            if "<WIM>" not in xml_str and "<IMAGE" not in xml_str:
                 return {"status": "encrypted", "message": "Encrypted XML Conetnt"}

            root = ET.fromstring(xml_str)

            if MODE == 0:
                print("\nFULL RAW XML (JSON) \n")
                print(json.dumps(xml_to_dict(root), indent=4))

            images = []
            for img in root.findall('IMAGE'):
                images.append(xml_to_dict(img))
                
            print(f"\n Succses! parsed {len(images)} indexes")
            return {"status": "ok", "images": clean_image_info(images)}

        except Exception as e:
            err_msg = str(e)
            if "Dead Link" in err_msg or "404" in err_msg or "403" in err_msg:
                print(f"DEAD LINK")
                return {"status": "error", "message": "Dead Link"}
            
            print(f"Retry: {err_msg[:20]}", end="\r")
            time.sleep(RETRY_DELAY)
            attempts += 1

    print(f"FAILED (Max Retreis)")
    return {"status": "error", "mesage": "Max Retries / Network Fail"}

def load_js_file(filepath):
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
    match = re.search(r'const\s+editions\s*=\s*({[\s\S]*});', content)
    if match:
        try:
            return json.loads(match.group(1))
        except json.JSONDecodeError:
            print("JSON Parse Error")
            sys.exit(1)
    return {}

def save_data_live(data):
    try:
        json_dump = json.dumps(data, indent=4)
        js_content = f"const editions = {json_dump};\n"
        with open(OUTPUT_FILE, 'w', encoding='utf-8') as f:
            f.write(js_content)
    except Exception as e:
        print(f"\n Failed to save live update: {e}")

def main():
    if MODE == 0:
        url = input("Paste Link: ").strip()
        if not url: return
        res = scan_esd_native(url)
        print(json.dumps(res, indent=4))
        return

    if not os.path.exists(INPUT_FILE):
        print(f"Error: {INPUT_FILE} not found")
        return

    data = load_js_file(INPUT_FILE)
    
    for build_key, editions in data.items():
        print(f"\nProcesing Build: {build_key}")
        
        for edition_key, languages in editions.items():
            print(f"Edition: {edition_key}")
            for lang_key, file_info in languages.items():

                if file_info.get('more_info') == 'Verified' and 'all_indexes' in file_info:
                    print(f"Language: {lang_key} [already Verified]")
                    continue

                if file_info.get('more_info') == 'Encrypted':
                    print(f"language: {lang_key} [already Encrypted]")
                    continue

                url = file_info.get('path')
                if not url: continue
                
                print(f"Language: {lang_key}")
                
                if url in URL_CACHE:
                    scan_result = URL_CACHE[url]
                    print("(Using Cached Metadata)")
                else:
                    scan_result = scan_esd_native(url)
                    URL_CACHE[url] = scan_result
                
                if scan_result['status'] == 'ok':
                    file_info['all_indexes'] = scan_result['images']
                    file_info['more_info'] = "Verified"
                    for k in ['wim_name', 'wim_build', 'wim_size_str', 'wim_edition_id', 'metadata_status']:
                        file_info.pop(k, None)

                elif scan_result['status'] == 'encrypted':
                    file_info['more_info'] = "Encrypted"
                    for k in ['wim_name', 'wim_build', 'wim_size_str', 'all_indexes', 'metadata_status']:
                        file_info.pop(k, None)

                else:
                    file_info['more_info'] = "N/A / Might be encrypted OR range not Supported"
                    for k in ['wim_name', 'wim_build', 'wim_size_str', 'all_indexes', 'metadata_status']:
                        file_info.pop(k, None)

                save_data_live(data)

if __name__ == "__main__":
    main()