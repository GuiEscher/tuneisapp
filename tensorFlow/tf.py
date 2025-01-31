import h5py

file_path = r"D:\tuneisappflutter\tuneisappflutter\tensorFlow\yolo11n-seg.h5"

if h5py.is_hdf5(file_path):
    print("O arquivo é um HDF5 válido.")
else:
    print("O arquivo NÃO é um HDF5 válido.")
