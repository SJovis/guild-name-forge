import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Guild Name Forge",
  description: "A community ritual for choosing a guild name.",
  icons: { icon: "favicon.svg" },
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
