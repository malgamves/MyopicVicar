

require 'spec_helper'

describe ImageUpload do
  SIMPLE_DIR = '/home/benwbrum/dev/freeukgen/mvuploads/simpletest'
  ZIP_DIR = '/home/benwbrum/dev/freeukgen/mvuploads/ziptest'
  MULTI_DIR = '/home/benwbrum/dev/freeukgen/mvuploads/multilevletest'
  HETERO_DIR = '/home/benwbrum/dev/freeukgen/mvuploads/heterogenoustest'
  PDF_DIR = '/home/benwbrum/dev/freeukgen/mvuploads/pdftest'


#  pending "basic stuff"
  
  it "can be instantiated" do
    ImageUpload.new.should be_an_instance_of(ImageUpload)
  end
  
  it "should be persisted" do
    ImageUpload.create(:upload_path => '/tmp').should be_persisted
  end
  
  it "should persist an upload directory" do
    iu = ImageUpload.new
    iu.upload_path = "/tmp"
    iu.save!
    id = iu.id
    iu2 = ImageUpload.find(id)
    iu2.upload_path.should eq("/tmp")
  end
  
  
  it "should check for valid upload directory" do
    iu = ImageUpload.new
    iu.upload_path = "foo"
    iu.should be_invalid
    iu.upload_path = '/tmp'
    iu.should be_valid
    
    TMPDIR = "/tmp/MyopicVicarTest"

    iu.upload_path = TMPDIR
    system("mkdir -p #{TMPDIR}")
    system("chmod ugo+rx #{TMPDIR}")
    iu.should be_valid

    system("chmod ugo-rx #{TMPDIR}")
    iu.should be_invalid
    system("chmod ugo+x #{TMPDIR}")
    iu.should be_invalid
    system("chmod ugo-x #{TMPDIR}")
    system("chmod ugo+r #{TMPDIR}")
    iu.should be_invalid
    system("chmod ugo+rx #{TMPDIR}")
    iu.should be_valid
    system("rmdir #{TMPDIR}")
    iu.should be_invalid
  end
 

  it "should copy to a working dir" do
    # create the dest dir
    iu=ImageUpload.new
    iu.upload_path=SIMPLE_DIR
    iu.initialize_working_dir
    wd = iu.originals_dir
    File.directory?(wd).should eq(true)


    # copy files over
    iu.copy_to_originals_dir
    old_ls = Dir.entries(iu.upload_path).sort
    new_ls = Dir.entries(wd).sort
    
    old_ls.should eq(new_ls)

    # 
  end
  
  it "should process files" do
    iu=ImageUpload.new
    iu.upload_path=SIMPLE_DIR
    iu.copy_to_originals_dir
    wd = iu.originals_dir
    iu.process_originals_dir(wd)

    iu.image_dir.count.should eq(1)
    iu.image_dir.first.image_file.count.should eq(Dir.glob(File.join(SIMPLE_DIR,"*")).count)
    
  end
  

  it "should unzip files" do 
    iu=ImageUpload.new
    iu.upload_path=ZIP_DIR
    iu.copy_to_originals_dir
    wd = iu.originals_dir
    iu.process_originals_dir(wd)

    # fs tests
    wd_ls = Dir.glob(File.join(wd,"*"))
    zd_ls = Dir.glob(File.join(wd,"Flintshire 1861","*"))
    wd_ls.count.should eq 2 # new dir and orig zipfile
    zd_ls.count.should eq 11
                     

    # db tests
    iu.image_dir.count.should eq(2)
    iu.image_dir.where(:path => /Flintshire.*/).first.image_file.count.should eq(11)
  end

  it "should unpack PDFs" do 
    iu=ImageUpload.new
    iu.upload_path=PDF_DIR
    iu.copy_to_originals_dir
    wd = iu.originals_dir
    iu.process_originals_dir(wd)

    # fs tests
    wd_ls = Dir.glob(File.join(wd,"*"))
    zd_ls = Dir.glob(File.join(wd,"SSCens Tutor_Hse_3p","*"))
    wd_ls.count.should eq 2 # new dir and orig zipfile
    zd_ls.count.should eq 5
                     

    # db tests
    iu.image_dir.count.should eq(2)
    iu.image_dir.where(:path => /SSCens.*/).first.image_file.count.should eq(5)
  end

  it "should only process image files" do
    iu=ImageUpload.new
    iu.upload_path=HETERO_DIR
    iu.copy_to_originals_dir
    wd = iu.originals_dir
    iu.process_originals_dir(wd)

    iu.image_dir.count.should eq(3+Dir.glob(File.join(HETERO_DIR,"*.zip")).count)
    iu.image_dir.first.image_file.count.should eq(Dir.glob(File.join(HETERO_DIR,"*.jpg")).count)
    
  end
  


end
