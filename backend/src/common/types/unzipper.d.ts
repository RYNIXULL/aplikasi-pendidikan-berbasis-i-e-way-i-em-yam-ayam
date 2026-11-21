declare module 'unzipper' {
  export interface ZipEntry {
    path: string;
    uncompressedSize: number;
  }
  export interface ZipDirectory {
    files: ZipEntry[];
  }
  export const Open: {
    buffer(buf: Buffer): Promise<ZipDirectory>;
  };
}
