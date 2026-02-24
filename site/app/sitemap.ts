import type { MetadataRoute } from "next";
import { siteConfig } from "@/lib/site-config";

const routes = [
  "",
  "/docs",
  "/docs/quickstart",
  "/docs/permissions",
  "/docs/troubleshooting",
  "/privacy",
];

export default function sitemap(): MetadataRoute.Sitemap {
  return routes.map((path) => ({
    url: `${siteConfig.docsBaseUrl}${path}`,
    lastModified: new Date(),
  }));
}
