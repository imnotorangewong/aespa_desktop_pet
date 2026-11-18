import AppKit
import ImageIO

enum PetGroup: String, CaseIterable {
    case aespa
    case ive = "IVE"

    var galleryTitle: String { self == .ive ? "IVE" : "Aespa" }
}

struct PetSkinDescriptor {
    let id: String
    let title: String
    let resource: String
    let group: PetGroup

    init(id: String, title: String, resource: String, group: PetGroup = .aespa) {
        self.id = id
        self.title = title
        self.resource = resource
        self.group = group
    }
}
struct LoadedPetSkin {let descriptor:PetSkinDescriptor;let sheet:CGImage;let frames:[[NSImage]]}
enum PetSkinRegistry {
    // Add validated, bundled skin resources here. Missing/invalid entries never become selectable.
    static let entries=[PetSkinDescriptor(id:"original",title:"Ning Ning",resource:"spritesheet-clean"),
        PetSkinDescriptor(id:"blue-cat",title:"Giselle",resource:"skin-blue-cat"),
        PetSkinDescriptor(id:"charcoal-cat",title:"Karina",resource:"skin-charcoal-cat"),
        PetSkinDescriptor(id:"heart-buddy",title:"Winter",resource:"skin-heart-buddy"),
        PetSkinDescriptor(id:"ive-green-clip",title:"GANGANJI",resource:"skin-ive-green-clip",group:.ive),
        PetSkinDescriptor(id:"ive-bell-tail",title:"DAL-E",resource:"skin-ive-bell-tail",group:.ive),
        PetSkinDescriptor(id:"ive-bow-chick",title:"NAORI",resource:"skin-ive-bow-chick",group:.ive),
        PetSkinDescriptor(id:"ive-pink-clip",title:"CHERRY",resource:"skin-ive-pink-clip",group:.ive),
        PetSkinDescriptor(id:"ive-heart-cheek",title:"CHEEZ",resource:"skin-ive-heart-cheek",group:.ive),
        PetSkinDescriptor(id:"ive-green-charm",title:"ERANG-E",resource:"skin-ive-green-charm",group:.ive)]
    static let rowCounts=[6,8,8,4,5,8,6,6,6,8,8]
    static func frames(_ sheet:CGImage)->[[NSImage]]? {
        guard sheet.width==1536,sheet.height==2288,let context=CGContext(data:nil,width:1536,height:2288,bitsPerComponent:8,bytesPerRow:1536*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue|CGBitmapInfo.byteOrder32Big.rawValue) else{return nil}
        context.draw(sheet,in:CGRect(x:0,y:0,width:1536,height:2288));guard let data=context.data?.assumingMemoryBound(to:UInt8.self) else{return nil}
        // Alpha coverage per occupied cell: reject blank frames and opaque rectangular backgrounds.
        var result=[[NSImage]]()
        for (row,count) in rowCounts.enumerated(){var line=[NSImage]();for col in 0..<count {
            guard let crop=sheet.cropping(to:CGRect(x:col*192,y:row*208,width:192,height:208)) else{return nil}
            var opaque=0,clear=0
            // Image bitmap rows match the source sheet cell coordinates.
            for y in row*208..<(row+1)*208 {for x in col*192..<(col+1)*192 {let alpha=data[(y*1536+x)*4+3];if alpha>8{opaque+=1}else{clear+=1}}}
            guard opaque>32,clear>32 else{return nil}
            line.append(NSImage(cgImage:crop,size:NSSize(width:192,height:208)))
        };result.append(line)}
        return result
    }
    static func load(_ entry:PetSkinDescriptor,url:URL?)->LoadedPetSkin? {
        guard let url=url,let size=(try? url.resourceValues(forKeys:[.fileSizeKey]))?.fileSize,size>0,size<=20_000_000,
              let source=CGImageSourceCreateWithURL(url as CFURL,nil),CGImageSourceGetType(source) as String? == "public.png",
              let props=CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [CFString:Any],props[kCGImagePropertyPixelWidth] as? Int==1536,props[kCGImagePropertyPixelHeight] as? Int==2288,
              let cg=CGImageSourceCreateImageAtIndex(source,0,nil),let frames=frames(cg) else{return nil}
        return LoadedPetSkin(descriptor:entry,sheet:cg,frames:frames)
    }
}
final class PetSkinStore {
    static let key="pet.selectedSkin.v1"
    let available:[LoadedPetSkin];private let defaults:UserDefaults
    private(set) var selectedID:String
    var current:LoadedPetSkin? {available.first{$0.descriptor.id==selectedID} ?? available.first{$0.descriptor.id=="original"}}
    init(defaults:UserDefaults = .standard,entries:[PetSkinDescriptor]=PetSkinRegistry.entries,resolve:(PetSkinDescriptor)->URL?={Bundle.main.url(forResource:$0.resource,withExtension:"png")}) {
        self.defaults=defaults;var seen=Set<String>()
        available=entries.filter{seen.insert($0.id).inserted}.compactMap{PetSkinRegistry.load($0,url:resolve($0))}
        let saved=defaults.string(forKey:Self.key) ?? "original"
        selectedID=available.contains{$0.descriptor.id==saved} ? saved:"original"
        if selectedID != saved{defaults.set(selectedID,forKey:Self.key)}
    }
    @discardableResult func select(_ id:String,apply:(LoadedPetSkin)->Bool)->Bool {
        guard let skin=available.first(where:{$0.descriptor.id==id}),apply(skin) else{return false}
        selectedID=id;defaults.set(id,forKey:Self.key);return true
    }
}
func petSkinSelfTest(){
    let suite="pet-skin-test-"+UUID().uuidString;let defaults=UserDefaults(suiteName:suite)!;defer{defaults.removePersistentDomain(forName:suite)}
    defaults.set("missing",forKey:PetSkinStore.key)
    let original=PetSkinRegistry.entries[0],missing=PetSkinDescriptor(id:"missing",title:"Missing",resource:"absent")
    let store=PetSkinStore(defaults:defaults,entries:[original,missing,original]);precondition(store.selectedID=="original" && store.available.count==1)
    let skin=store.current!;precondition(skin.frames.map{$0.count}==PetSkinRegistry.rowCounts && skin.frames.flatMap{$0}.count==73)
    let view=PetView(sheet:skin.sheet);let timer=view.timer;view.row=3;view.frameIndex=2;view.action=true
    precondition(store.select("original"){view.applySkin($0)} && view.timer === timer && view.row==0 && !view.action)
    precondition(!store.select("missing"){_ in fatalError("missing skin must not apply")})
    precondition(!store.select("original"){_ in false});precondition(PetSkinStore(defaults:defaults).selectedID=="original")
    // A test-only alias exercises alternate-ID persistence without shipping a placeholder skin.
    let alias=PetSkinDescriptor(id:"test-alias",title:"Test only",resource:"spritesheet-clean")
    let alternate=PetSkinStore(defaults:defaults,entries:[original,alias]);precondition(alternate.select("test-alias"){view.applySkin($0)})
    precondition(PetSkinStore(defaults:defaults,entries:[original,alias]).selectedID=="test-alias")
    precondition(PetSkinStore(defaults:defaults,entries:[original]).selectedID=="original")
    let actual=PetSkinStore(defaults:defaults)
    let bundled=PetSkinRegistry.entries.filter{Bundle.main.url(forResource:$0.resource,withExtension:"png") != nil}
    precondition(actual.available.count==bundled.count)
    for candidate in actual.available {
        precondition(candidate.frames.map{$0.count}==PetSkinRegistry.rowCounts)
        precondition(actual.select(candidate.descriptor.id){view.applySkin($0)})
        precondition(view.timer === timer && view.frames[0][0] === candidate.frames[0][0])
        precondition(PetSkinStore(defaults:defaults).selectedID==candidate.descriptor.id)
        let missingSelected=PetSkinStore(defaults:defaults,resolve:{entry in entry.id==candidate.descriptor.id && entry.id != "original" ? nil:Bundle.main.url(forResource:entry.resource,withExtension:"png")})
        precondition(missingSelected.selectedID=="original")
        let preview=CGContext(data:nil,width:768,height:336,bitsPerComponent:8,bytesPerRow:768*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        preview.setFillColor(NSColor(calibratedWhite:0.85,alpha:1).cgColor);preview.fill(CGRect(x:0,y:0,width:768,height:336))
        var rendered=0
        for (r,line) in candidate.frames.enumerated(){for c in line.indices {
            view.row=r;view.frameIndex=c
            let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds)!;view.cacheDisplay(in:view.bounds,to:bitmap)
            precondition(bitmap.pixelsWide>=192 && bitmap.pixelsHigh>=208)
            let cg=line[c].cgImage(forProposedRect:nil,context:nil,hints:nil)!
            precondition(cg.width==192 && cg.height==208)
            if r>=9 {preview.draw(cg,in:CGRect(x:c*96,y:(10-r)*104,width:96,height:104))}
            if r==0 && c==0 {preview.draw(cg,in:CGRect(x:0,y:208,width:96,height:104))}
            rendered+=1
        }}
        precondition(rendered==73)
        for i in 0..<16 {let radians=Double(i)*Double.pi/8;let mapped=lookIndex(dx:sin(radians)*100,dy:cos(radians)*100)!;precondition(mapped==i && candidate.frames[9+mapped/8][mapped%8].size==NSSize(width:192,height:208))}
        let output=NSBitmapImageRep(cgImage:preview.makeImage()!).representation(using:.png,properties:[:])!
        try! output.write(to:URL(fileURLWithPath:"/tmp/skin-preview-"+candidate.descriptor.id+".png"))
        let icon=PetMenuIcon.makeRestart(sheet:candidate.sheet)!;precondition(icon.size==NSSize(width:16,height:16))
        print("PASS: bundled skin",candidate.descriptor.id,"73 offscreen frames, 16 clockwise look mappings, switch/reload/missing fallback, menu icon")
    }
    let prefs=PetMenuPreferences(defaults:defaults)
    let settingsOwner=NSWindow(contentRect:NSRect(x:0,y:0,width:192,height:208),styleMask:[.borderless],backing:.buffered,defer:false)
    let settings=PetSettingsController(owner:settingsOwner,preferences:prefs,skins:actual,onSkinChange:{view.applySkin($0)})
    let groups = PetGroup.allCases.filter { group in actual.available.contains { $0.descriptor.group == group } }
    precondition(settings.groupPicker.itemTitles == groups.map { $0.rawValue })
    for group in groups {
        let initialID = actual.selectedID
        settings.groupPicker.selectItem(withTitle:group.rawValue)
        settings.changeGroup()
        precondition(actual.selectedID == initialID)
        let members = actual.available.filter { $0.descriptor.group == group }
        precondition(settings.skinPicker.itemArray.compactMap { $0.representedObject as? String } == members.map { $0.descriptor.id })
        for member in members {
            settings.skinPicker.selectItem(withTitle:member.descriptor.title)
            settings.changeSkin()
            precondition(actual.selectedID == member.descriptor.id && defaults.string(forKey:PetSkinStore.key) == actual.selectedID)
        }
        settings.show()
        precondition(settings.groupPicker.titleOfSelectedItem == group.rawValue && settings.skinPicker.titleOfSelectedItem == actual.current?.descriptor.title)
        settings.hide()
    }
    print("PASS: grouped picker, browsing without applying, switching, reopening and saved IDs")
    let solidContext=CGContext(data:nil,width:1536,height:2288,bitsPerComponent:8,bytesPerRow:6144,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
    solidContext.setFillColor(NSColor.purple.cgColor);solidContext.fill(CGRect(x:0,y:0,width:1536,height:2288));precondition(PetSkinRegistry.frames(solidContext.makeImage()!)==nil)
    let bad=CGContext(data:nil,width:16,height:16,bitsPerComponent:8,bytesPerRow:64,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!;precondition(PetSkinRegistry.frames(bad)==nil)
    let blank=CGContext(data:nil,width:1536,height:2288,bitsPerComponent:8,bytesPerRow:6144,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!;precondition(PetSkinRegistry.frames(blank)==nil)
    print("PASS: skin registry missing/duplicate/fallback, 73-frame validation, blank/wrong dimensions, persistence and same-view/timer atomic switch")
}
